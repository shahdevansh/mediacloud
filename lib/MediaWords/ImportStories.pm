package MediaWords::ImportStories;

=head1 NAME

Mediawords::ImportStories - template class for importing stories into db

=head1 DESCRIPTION

Import stories into the database, handling date bounding and story deduping.  This is only
a template class.  You must use of the sub class such as MediaWords::ImportStories::ScrapeHTML
or MediaWords::ImportStories::Feedly to import stories from a given source.

After the sub class identifies all story candidates, ImportStories looks for any
duplicates among the story candidates and the existing stories in the media sources and only adds as stories
the candidates with out existing duplicate stories.  The duplication check looks for matching normalized urls
as well as matching title parts (see MediaWords::DBI::Stories::get_medium_dup_stories_by_<title|url>.

Each sub class needs to implement $self->get_new_stories(), which should return a set of story candidates
for deduplication and date restriction by this super class.

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose::Role;

use Data::Dumper;
use Encode;
use List::MoreUtils;
use Parallel::ForkManager;

use MediaWords::TM::GuessDate;
use MediaWords::CommonLibs;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use MediaWords::Util::HTML;
use MediaWords::Util::SQL;
use MediaWords::Util::Tags;
use MediaWords::Util::URL;

=head1 ATTRIBUTES

=over

item *

db - db handle

item *

media_id - media source to which to add stories

item *

max_pages (optional) - max num of pages to scrape by recursively finding urls matching page_url_pattern

item *

start_date (optional) - start date of stories to scrape and dedup

item *

end_date (optional) - end date of stories to scrape and dedup

item *

debug (optional) - print debug messages urls crawled and stories created

item *

dry_run (optional) - do everything but actually insert stories into db

item *

module_stories - full list of stories returned by call to $self->get_new_stories() during scrape_stories()

item *

existing_stories - full list of stories in media_id, genreated during scrape_stories()

=back

=cut

has 'db'       => ( is => 'rw', isa => 'Ref', required => 1 );
has 'media_id' => ( is => 'rw', isa => 'Int', required => 1 );

has 'debug'   => ( is => 'rw', isa => 'Int', required => 0 );
has 'dry_run' => ( is => 'rw', isa => 'Int', required => 0 );

has 'max_pages' => ( is => 'rw', isa => 'Int', required => 0, default => 10_000 );

has 'start_date' => ( is => 'rw', isa => 'Str', required => 0, default => '1000-01-01' );
has 'end_date'   => ( is => 'rw', isa => 'Str', required => 0, default => '3000-01-01' );

has 'scrape_feed' => ( is => 'rw', isa => 'Ref', required => 0 );

has 'module_stories'   => ( is => 'rw', isa => 'Ref', required => 0 );
has 'existing_stories' => ( is => 'rw', isa => 'Ref', required => 0 );

# sub class must implement $self->get_new_stories(), which returns story objects that have not yet
# been inserted into the db
requires 'get_new_stories';

=head1 METHODS

=cut

=head2 generate_story( $self, $contnet, $url )

Given the content, generate a story hash

=cut

sub generate_story
{
    my ( $self, $content, $url ) = @_;

    my $db = $self->db;

    my $title = MediaWords::Util::HTML::html_title( $content, $url, 1024 );

    my $story = {
        url          => $url,
        guid         => $url,
        media_id     => $self->media_id,
        collect_date => MediaWords::Util::SQL::sql_now,
        title        => $title,
        description  => '',
        content      => $content
    };

    my $date_guess = MediaWords::TM::GuessDate::guess_date( $db, $story, $content );
    if ( $date_guess->{ result } eq $MediaWords::TM::GuessDate::Result::FOUND )
    {
        $story->{ publish_date } = $date_guess->{ date };
    }
    else
    {
        $story->{ publish_date } = MediaWords::Util::SQL::sql_now();
    }

    $story->{ content } = $content;

    return $story;
}

=head2 story_is_in_date_range( $self, $publish_date )

Return true if the publish date is before $self->end_date and after $self->start_date

=cut

sub story_is_in_date_range
{
    my ( $self, $publish_date ) = @_;

    my $publish_day = substr( $publish_date, 0, 10 );

    my $start_date = substr( $self->start_date, 0, 10 ) || '2010-01-01';
    return 0 if ( $start_date && ( $publish_day lt $start_date ) );

    my $end_date = substr( $self->end_date, 0, 10 );
    return 0 if ( $end_date && ( $publish_day gt $end_date ) );

    return 1;
}

sub _get_stories_in_date_range
{
    my ( $self, $stories ) = @_;

    DEBUG "date range: " . $self->start_date . " - " . $self->end_date;

    my $dated_stories = [];
    for my $story ( @{ $stories } )
    {
        if ( $self->story_is_in_date_range( $story->{ publish_date } ) )
        {
            push( @{ $dated_stories }, $story );
        }
        else
        {
            DEBUG "story failed date restriction: " . $story->{ publish_date };
        }
    }

    DEBUG "kept " . scalar( @{ $dated_stories } ) . " / " . scalar( @{ $stories } ) . " after date restriction";

    return $dated_stories;
}

# declare a cursor for the get_existing_stories query so that postgres can process the query while the underlying
# module processes $self->get_new_stories()
sub _declare_existing_stories_cursor
{
    my ( $self ) = @_;

    $self->db->query( <<SQL, $self->{ media_id } );
declare EXISTING_STORIES cursor for
    select stories_id, media_id, publish_date, url, guid, title from stories where media_id = ?
SQL

}

# get all stories belonging to the media source
sub _get_existing_stories
{
    my ( $self ) = @_;

    my $stories = $self->db->query( "fetch all from EXISTING_STORIES" )->hashes;

    return $stories;
}

# give a list of dup stories returned by  MediaWords::DBI::Stories::get_medium_dup_stories_by_*, prune the
# original list only to include one each of the sets of dup stories
sub _prune_dup_stories($$)
{
    my ( $self, $stories, $dup_sets ) = @_;

    my $remove_stories_lookup = {};

    for my $dup_set ( @{ $dup_sets } )
    {
        # mark all stories in the dup set other than the first for removal
        shift( @{ $dup_set } );
        map { $remove_stories_lookup->{ $_->{ guid } } = 1 } @{ $dup_set };
    }

    my $pruned_stories = [];
    map { push( @{ $pruned_stories }, $_ ) unless ( $remove_stories_lookup->{ $_->{ guid } } ) } @{ $stories };

    DEBUG "pruned to " . scalar( @{ $pruned_stories } ) . " / " . scalar( @{ $stories } ) . " stories";

    return $pruned_stories;
}

# dedup the stories from the import module first
sub _dedup_imported_stories($$)
{
    my ( $self, $stories ) = @_;

    my $url_dup_stories = MediaWords::DBI::Stories::get_medium_dup_stories_by_url( $self->db, $stories );

    my $deduped_stories = $self->_prune_dup_stories( $stories, $url_dup_stories );

    my $title_dup_stories = MediaWords::DBI::Stories::get_medium_dup_stories_by_title( $self->db, $deduped_stories, 1 );

    return $self->_prune_dup_stories( $deduped_stories, $title_dup_stories );
}

# return a list of just the new stories that don't have a duplicate in the existing stories
sub _dedup_new_stories
{
    my ( $self ) = @_;

    my $new_stories      = $self->module_stories;
    my $existing_stories = $self->existing_stories;

    $new_stories = $self->_dedup_imported_stories( $new_stories );

    my $all_stories = [ @{ $new_stories }, @{ $existing_stories } ];

    my $all_dup_stories = MediaWords::DBI::Stories::get_medium_dup_stories_by_url( $self->db, $all_stories );
    my $title_dup_stories = MediaWords::DBI::Stories::get_medium_dup_stories_by_title( $self->db, $all_stories, 1 );

    push( @{ $all_dup_stories }, @{ $title_dup_stories } );

    my $new_stories_lookup = {};
    map { $new_stories_lookup->{ $_->{ url } } = $_ } @{ $new_stories };

    my $dup_new_stories_lookup = {};
    for my $dup_stories ( @{ $all_dup_stories } )
    {
        my $stories_id = 0;
        map { $stories_id ||= $_->{ stories_id } } @{ $dup_stories };

        for my $ds ( @{ $dup_stories } )
        {
            if ( $new_stories_lookup->{ $ds->{ url } } )
            {
                delete( $new_stories_lookup->{ $ds->{ url } } );
                $dup_new_stories_lookup->{ $ds->{ url } } = $ds;
                $ds->{ dup_stories_id } = $stories_id;
            }
        }

    }

    my $nondup_stories = [ values( %{ $new_stories_lookup } ) ];
    my $dup_stories    = [ values( %{ $dup_new_stories_lookup } ) ];

    DEBUG "_dedup_new_stories: " . scalar( @{ $nondup_stories } ) . " new / " . scalar( @{ $dup_stories } ) . " dup";

    return ( $nondup_stories, $dup_stories );
}

# get a dummy feed just to hold the scraped stories because we have to give a feed to each new download
sub _get_scrape_feed
{
    my ( $self ) = @_;

    return $self->scrape_feed if ( $self->scrape_feed );

    my $db = $self->db;

    my $medium = $db->find_by_id( 'media', $self->media_id );

    my $feed_name = ref( $self );
    my $feed_url  = "$feed_name:$medium->{ url }";

    my $feed = $db->query( <<SQL, $medium->{ media_id }, $feed_url, $feed_name )->hash;
select * from feeds where media_id = ? and url = ? order by ( name = ? )
SQL

    $feed ||= $db->query( <<SQL, $medium->{ media_id }, $feed_url, $feed_name )->hash;
insert into feeds ( media_id, url, name, feed_status ) values ( ?, ?, ?, 'inactive' ) returning *
SQL

    DEBUG "scrape feed: $feed->{ name } [$feed->{ feeds_id }]";

    $self->scrape_feed( $feed );

    return $feed;
}

# add story to a special 'scrape' feed
sub _add_story_to_scrape_feed
{
    my ( $self, $story ) = @_;

    $self->db->query( <<SQL, $self->_get_scrape_feed->{ feeds_id }, $story->{ stories_id } );
insert into feeds_stories_map ( feeds_id, stories_id ) values ( ?, ? )
SQL

}

# download the content for the story's url
sub _get_story_content
{
    my ( $self, $url ) = @_;

    DEBUG "fetching story url $url";

    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_timing( '1,2,4,8' );

    my $res = $ua->get( $url );

    if ( $res->is_success )
    {
        return $res->decoded_content;
    }
    else
    {
        WARN "Unable to fetch content for story '$url'";
        return '';
    }

}

# add and extract download for story
sub _add_story_download
{
    my ( $self, $story, $content ) = @_;

    my $db = $self->db;

    if ( $content )
    {
        my $download = {
            feeds_id   => $self->_get_scrape_feed->{ feeds_id },
            stories_id => $story->{ stories_id },
            url        => $story->{ url },
            host       => MediaWords::Util::URL::get_url_host( $story->{ url } ),
            type       => 'content',
            sequence   => 1,
            state      => 'success',
            path       => 'content:pending',
            priority   => 1,
            extracted  => 't'
        };

        $download = $db->create( 'downloads', $download );

        $download = MediaWords::DBI::Downloads::store_content( $db, $download, \$content );

        eval { MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download ); };

        WARN "extract error processing download $download->{ downloads_id }: $@" if ( $@ );
    }
    else
    {
        my $download = {
            feeds_id   => $self->_get_scrape_feed->{ feeds_id },
            stories_id => $story->{ stories_id },
            url        => $story->{ url },
            host       => MediaWords::Util::URL::get_url_host( $story->{ url } ),
            type       => 'content',
            sequence   => 1,
            state      => 'pending',
            priority   => 1,
            extracted  => 'f'
        };

        $download = $db->create( 'downloads', $download );
    }
}

# add row to scraped_stories table
sub _add_scraped_stories_flag
{
    my ( $self, $story ) = @_;

    $self->db->query( <<SQL, $story->{ stories_id }, ref( $self ) );
insert into scraped_stories ( stories_id, import_module )
    select \$1, \$2 where not exists (
        select 1 from scraped_stories where stories_id = \$1 and import_module = \$2 )
SQL

}

# add the stories to the database, including downloads
sub _add_new_stories
{
    my ( $self, $stories ) = @_;

    DEBUG "adding new stories to db ..." if ( $self->debug );

    my $total_stories = scalar( @{ $stories } );
    my $i             = 1;

    my $added_stories = [];
    for my $story ( @{ $stories } )
    {
        $self->db->begin;
        DEBUG "story: " . $i++ . " / $total_stories";

        my $content = $story->{ content };

        delete( $story->{ content } );
        delete( $story->{ normalized_url } );

        eval { $story = $self->db->create( 'stories', $story ) };
        if ( $@ )
        {
            # it's quicker to just rely on postgres to catch constrained dups than to check for them first
            if ( $@ =~ /unique constraint "([^"]*)"/ )
            {
                DEBUG( "skipping postgres dup: $1" );
            }
            else
            {
                LOGCARP( $@ . " - " . Dumper( $story ) );
            }

            $self->db->rollback;
            next;
        }

        $self->_add_scraped_stories_flag( $story );

        $self->_add_story_to_scrape_feed( $story );

        $self->_add_story_download( $story, $content );

        push( @{ $added_stories }, $story );
        $self->db->commit;
    }

    return $added_stories;
}

# print stories
sub _print_stories
{
    my ( $self, $stories ) = @_;

    for my $s ( sort { $a->{ publish_date } cmp $b->{ publish_date } } @{ $stories } )
    {
        DEBUG <<END;
$s->{ publish_date } - $s->{ title } [$s->{ url }]
END
    }

}

# print list of deduped stories and dup stories
sub _print_story_diffs
{
    my ( $self, $deduped_stories, $dup_stories ) = @_;

    return unless ( $self->debug );

    DEBUG "dup stories:";
    $self->_print_stories( $dup_stories );

    DEBUG "deduped stories:";
    $self->_print_stories( $deduped_stories );

}

# narrow date range to the dates of the new stories
sub _narrow_dates_to_new_stories
{
    my ( $self, $new_stories ) = @_;

    $new_stories = [ sort { $a->{ publish_date } cmp $b->{ publish_date } } @{ $new_stories } ];

    my $earliest_story = $new_stories->[ 0 ];
    my $latest_story   = pop( @{ $new_stories } );

    if ( !$self->start_date || ( $earliest_story->{ publish_date } gt $self->start_date ) )
    {
        $self->start_date( $earliest_story->{ publish_date } );
    }

    if ( !$self->end_date || ( $latest_story->{ publish_date } lt $self->end_date ) )
    {
        $self->end_date( $latest_story->{ publish_date } );
    }
}

# eliminate any stories with titles that are logogram language (chinese, japanese, etc) because story deduplication
# does not work well
sub _eliminate_logogram_languages()
{
    my ( $self ) = @_;

    my $logogram_lookup = { ja => 1, ko => 1, zh => 1, dz => 1, bo => 1 };

    my $keep_stories = [];
    my $stories      = $self->module_stories;

    for my $story ( @{ $stories } )
    {
        my $language = MediaWords::Util::IdentifyLanguage::language_code_for_text( $story->{ title } );
        push( @{ $keep_stories }, $story ) if ( !$logogram_lookup->{ $language } );
    }

    $self->module_stories( $keep_stories );

    if ( scalar( @{ $stories } ) > scalar( @{ $keep_stories } ) )
    {
        DEBUG "pruned from " .
          scalar( @{ $stories } ) . " to " .
          scalar( @{ $keep_stories } ) . " stories for logogram language";
    }
}

# get module stories and existing stories and set ->module_stories and ->existing_stories
sub _get_module_and_existing_stories
{
    my ( $self ) = @_;

    # transaction is needed for the duraction of the cursor
    $self->db->begin;

    eval {
        $self->_declare_existing_stories_cursor();

        $self->module_stories( $self->get_new_stories );

        $self->_eliminate_logogram_languages();

        return unless ( scalar( @{ $self->module_stories } ) );

        $self->existing_stories( $self->_get_existing_stories() );
    };

    $self->db->commit;

    die( $@ ) if ( $@ );
}

=head2 scrape_stories( $self, $new_stories )

Call ImportStories::SUB->get_new_stories and add any stories within the specified date range to the given media source
if there are not already duplicates in the media source.

If $new_stories is not passed, call $self->get_new_stories() to get the list of new stories from the import module. If
$new_stories is specified, use that list instead of calling $self->get_new_stories().
=cut

sub scrape_stories
{
    my ( $self ) = @_;

    $self->_get_module_and_existing_stories();

    my $new_stories = $self->module_stories;

    return [] unless ( scalar( @{ $new_stories } ) );

    my $dated_stories = $self->_get_stories_in_date_range( $new_stories );

    my ( $deduped_new_stories, $dup_new_stories ) = $self->_dedup_new_stories();

    $self->_print_story_diffs( $deduped_new_stories, $dup_new_stories ) if ( $self->debug );

    if ( $self->dry_run )
    {
        return $deduped_new_stories;
    }
    else
    {
        return $self->_add_new_stories( $deduped_new_stories );
    }
}

1;
