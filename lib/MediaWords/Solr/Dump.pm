package MediaWords::Solr::Dump;

=head1 NAME

MediaWords::Solr::Dump - import story_sentences from postgres into solr

=head1 SYNOPSIS

    # generate dumped csv files and then import those csvs into solr
    MediaWords::Solr::Dump::generate_and_import_data( $delta, $delete_all, $staging, $jobs );

    # dump solr data from postgres into csvs
    MediaWords::Solr::Dump::print_csv_to_file( $db, $file_spec, $jobs, $delta, $min_proc, $max_proc );

    # import already dumped csv files
    MediaWords::Solr::Dump::import_csv_files( $files, $delta, $staging, $jobs );

=head1 DESCRIPTION

We import any updated story_sentences into solr from the postgres server by periodically script on the solr server.
This module implements the functionality of that script, as well as functionality to just dump import csvs from
postgres and to import already existing csvs into solr.

The module knows which sentences to import by keep track of db_row_last_updated fields on the stories, media, and
story_sentences table.  The module queries story_sentences for all distinct stories for which the db_row_last_updated
value is greater than the latest value in solr_imports.  Triggers in the postgres database update the
story_sentences.db_row_last_updated value on story_sentences whenever a related story, medium, story tag, story sentence
tag, or story sentence tag is updated.

In addition to the incremental imports by db_row_last_updated, we import any stories in solr_import_extra_stories,
in chunks up to 100k until the solr_import_extra_stories queue has been cleared.  In addition to using the queue to
manually trigger updates for specific stories, we use it to queue updates for entire media sources whose tags have been
changed and to queue updates for stories whose bitly data have been updated.

The module is carefully implemented to optimize the speed of querying from postgres in a few ways:

=over

=item *

The module is designed to be able to stream data from postgres using server side cursors, so that the script can write
the csv lines for rows as they are read by postgres, rather than waiting for postgres to fetch its whole result
set into memory and return the whole set at once.

=item *

In order to allow postgres to stream the results, we do all joins on the client side rather than on the postgres side.
If you look at the implementation code, you'll see lots of references to data_lookups for various related tables
(processed stories, stories tags, media tags, bitly clicks, etc).

=item *

When streaming large files like this, postgres is much faster running several streaming queries are once rather than
just one.  This is why all of the csv dumping code is parallelized.  We run parallel queries by modding the stories_id
to speed up the dump process.

=item *

For the import of the csvs, we use the /solr/update/csv solr web service end point.  But we feed the csv to the solr
service through http rather than providing a local file so that we can track and resume the import process.

=item *

We track which parts of which csv files have already been imported so that we can resume an import process that failed
or had an error in some part.  This is because production import of our entire database can take a few days, so it is
important to be recover from an error without having to restart the whole process.

The import functions in this module accept a $staging parameter.  If this parameter is set to true, the data is imported
into the staging database rather than that production database.  MediaWords::Solr::swap_live_collection is used to
swap the production and staging databases.

=back

=cut

#use forks;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use CHI;
use Data::Dumper;
use Digest::MD5;
use Encode;
use File::Basename;
use File::ReadBackwards;
use FileHandle;
use List::MoreUtils;
use List::Util;
use Parallel::ForkManager;
use Readonly;
use Text::CSV_XS;
use URI;

require bytes;    # do not override length() and such

use MediaWords::DB;
use MediaWords::Util::Config;
use MediaWords::Util::JSON;
use MediaWords::Util::Paths;
use MediaWords::Util::Web;
use MediaWords::Solr;

my $_solr_select_url;

# order and names of fields exported to and imported from csv
Readonly my @CSV_FIELDS =>
  qw/stories_id media_id story_sentences_id solr_id publish_date publish_day sentence_number sentence title language
  bitly_click_count processed_stories_id tags_id_media tags_id_stories tags_id_story_sentences timespans_id/;

# numbner of lines in each chunk of csv to import
Readonly my $CSV_CHUNK_LINES => 10_000;

# how many sentences to fetch at a time from the postgres query
Readonly my $FETCH_BLOCK_SIZE => 10_000;

# mark date before generating dump for storing in solr_imports after successful import
my $_import_date;

=head2 FUNCTIONS

=cut

# run a postgres query and generate a table that lookups on the first column by the second column.
# assign that lookup to $data_lookup->{ $name }.
sub _set_lookup
{
    my ( $db, $data_lookup, $name, $query ) = @_;

    my $res = $db->query( $query );

    my $lookup = {};
    while ( my $row = $res->array )
    {
        $lookup->{ $row->[ 1 ] } = $row->[ 0 ];
    }

    $data_lookup->{ $name } = $lookup;
}

# add enough stories from the solr_import_extra_stories queue to the delta_import_stories table that there are up to
# _get_maxed_queued_stories in delta_import_stories for each solr_import
sub _add_extra_stories_to_import
{
    my ( $db, $import_date, $num_delta_stories, $num_proc, $proc ) = @_;

    my $config = MediaWords::Util::Config::get_config;

    my $conf_max_queued_stories = $config->{ mediawords }->{ solr_import }->{ max_queued_stories };

    my $max_processed_stories = int( $conf_max_queued_stories / $num_proc );

    my $max_queued_stories = List::Util::max( 0, $max_processed_stories - $num_delta_stories );

    # first import any stories from snapshotted topics so that those snapshots become searchable ASAP.
    # do this as a separate query because I couldn't figure out a single query that resulted in a reasonable
    # postgres query plan given a very large solr_import_extra_stories table
    my $num_queued_stories = $db->query(
        <<"SQL",
        INSERT INTO delta_import_stories (stories_id)
            SELECT distinct sies.stories_id
            FROM solr_import_extra_stories sies
                join snap.stories ss using ( stories_id )
                join snapshots s on ( ss.snapshots_id = s.snapshots_id and not s.searchable )
            WHERE MOD( sies.stories_id, $num_proc ) = ( $proc - 1 )
            ORDER BY sies.stories_id
            LIMIT ?
SQL
        $max_queued_stories
    )->rows;

    INFO "added $num_queued_stories topic stories to the import";

    $max_queued_stories -= $num_queued_stories;

    # order by stories_id so that we will tend to get story_sentences in chunked pages as much as possible; just using
    # random stories_ids for collections of old stories (for instance queued to solr_import_extra_stories from a
    # media tag update) can make this query a couple orders of magnitude slower
    $num_queued_stories += $db->query(
        <<"SQL",
        INSERT INTO delta_import_stories (stories_id)
            SELECT stories_id
            FROM solr_import_extra_stories s
            WHERE MOD( stories_id, $num_proc ) = ( $proc - 1 )
            ORDER BY stories_id
            LIMIT ?
SQL
        $max_queued_stories
    )->rows;

    if ( $num_queued_stories > 0 )
    {
        # use pg_class estimate to avoid expensive count(*) query
        my ( $total_queued_stories ) = $db->query(
            <<SQL
            SELECT reltuples::bigint
            FROM pg_class
            WHERE relname = 'solr_import_extra_stories'
SQL
        )->flat;

        INFO "added $num_queued_stories out of about $total_queued_stories queued stories to the import";
    }

}

# setup 'csr' cursor in postgres as the query to import the story_sentences.  we use a server side cursor so that
# we can stream data to the csv as postgres fetches it from disk.
sub _declare_sentences_cursor
{
    my ( $db, $delta, $num_proc, $proc ) = @_;

    my $delta_clause = $delta ? 'and ss.stories_id in ( select stories_id from delta_import_stories )' : '';

    # DO NOT ADD JOINS TO THIS QUERY! INSTEAD ADD ANY JOINED TABLES TO _get_data_lookup AND THEN ADD TO THE CSV
    # IN _print_csv_to_file_from_csr. see pod description above for more info.
    $db->query( <<END );
declare csr cursor for

    select
        ss.stories_id,
        ss.media_id,
        ss.story_sentences_id,
        ss.stories_id || '!' || ss.story_sentences_id solr_id,
        to_char( date_trunc( 'minute', publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_date,
        to_char( date_trunc( 'hour', publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_day,
        ss.sentence_number,
        ss.sentence,
        null title,
        ss.language

    from story_sentences ss

    where (MOD(ss.stories_id, $num_proc) = $proc - 1)
        $delta_clause
END

}

# setup 'csr' cursor in postgres as the query to import the story titles.  we use a server side cursor so that
# we can stream data to the csv as postgres fetches it from disk.
sub _declare_titles_cursor
{
    my ( $db, $delta, $num_proc, $proc ) = @_;

    my $delta_clause = $delta ? 'and s.stories_id in ( select stories_id from delta_import_stories )' : '';

    # DO NOT ADD JOINS TO THIS QUERY! INSTEAD ADD ANY JOINED TABLES TO _get_data_lookup AND THEN ADD TO THE CSV
    # IN _print_csv_to_file_from_csr. see pod description above for more info.
    $db->query( <<END );
declare csr cursor for

    select
        s.stories_id,
        s.media_id,
        0 story_sentences_id,
        s.stories_id || '!' || 0 solr_id,
        to_char( date_trunc( 'minute', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_date,
        to_char( date_trunc( 'hour', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_day,
        0 as sentence_number,
        null sentence,
        s.title,
        s.language

    from stories s

    where MOD( s.stories_id, $num_proc ) = $proc - 1
        $delta_clause
END

}

# incrementally read the results from the 'csr' postgres cursor and print out the resulting sorl dump csv to the file
sub _print_csv_to_file_from_csr
{
    my ( $db, $fh, $data_lookup, $print_header ) = @_;

    my $fields = \@CSV_FIELDS;

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    if ( $print_header )
    {
        $csv->combine( @{ $fields } );
        $fh->print( $csv->string . "\n" );
    }

    my $imported_stories_ids = {};
    my $i                    = 0;
    while ( 1 )
    {
        my $rows = $db->query( "fetch $FETCH_BLOCK_SIZE from csr" )->hashes;
        if ( scalar( @{ $rows } ) == 0 )
        {
            last;
        }

        foreach my $row ( @{ $rows } )
        {
            my $stories_id         = $row->{ stories_id };
            my $media_id           = $row->{ media_id };
            my $story_sentences_id = $row->{ story_sentences_id };

            my $processed_stories_id = $data_lookup->{ ps }->{ $stories_id };
            next unless ( $processed_stories_id );

            my $click_count       = $data_lookup->{ bitly_clicks }->{ $stories_id } || '';
            my $media_tags_list   = $data_lookup->{ media_tags }->{ $media_id }     || '';
            my $stories_tags_list = $data_lookup->{ stories_tags }->{ $stories_id } || '';
            my $timespans_list    = $data_lookup->{ timespans }->{ $stories_id }    || '';

            # replacing ss tags with stories tags because ss tags are killing performance of the import
            # are we are switching to stories tags soon any way
            my $ss_tags_list = $stories_tags_list;

            $csv->combine(
                $stories_id,                  #
                $media_id,                    #
                $story_sentences_id,          #
                $row->{ solr_id },            #
                $row->{ publish_date },       #
                $row->{ publish_day },        #
                $row->{ sentence_number },    #
                $row->{ sentence },           #
                $row->{ title },              #
                $row->{ language },           #
                $click_count,                 #
                $processed_stories_id,        #
                $media_tags_list,             #
                $stories_tags_list,           #
                $ss_tags_list,                #
                $timespans_list,              #
            );
            $fh->print( encode( 'utf8', $csv->string . "\n" ) );

            $imported_stories_ids->{ $stories_id } = 1;
        }

        INFO time() . " " . ( ++$i * $FETCH_BLOCK_SIZE );    # unless ( ++$i % 10 );
    }

    $db->query( "close csr" );

    return [ keys %{ $imported_stories_ids } ];
}

# limit delta_import_stories to max_queued_stories stories;  put excess stories in solr_extra_import_stories
sub _restrict_delta_import_stories_size ($$)
{
    my ( $db, $num_delta_stories ) = @_;

    my $max_queued_stories = MediaWords::Util::Config::get_config->{ mediawords }->{ solr_import }->{ max_queued_stories };

    return if ( $num_delta_stories <= $max_queued_stories );

    DEBUG( "cutting delta import stories from $num_delta_stories to $max_queued_stories stories" );

    $db->query( <<SQL, $max_queued_stories );
create temporary table keep_ids as
    select * from delta_import_stories order by stories_id limit ?
SQL

    $db->query( "delete from delta_import_stories where stories_id in ( select stories_id from keep_ids )" );

    $db->query( "insert into solr_import_extra_stories ( stories_id ) select stories_id from delta_import_stories" );

    $db->query( "drop table delta_import_stories" );

    $db->query( "alter table keep_ids rename to delta_import_stories" );

}

# get the delta clause that restricts the import of all subsequent queries to just the delta stories.  uses
# a temporary table called delta_import_stories to list which stories should be imported.  we do this instead
# of trying to query the date direclty because we need to restrict by this list in stand alone queries to various
# manually joined tables, like stories_tags_map.
sub _create_delta_import_stories
{
    my ( $db, $num_proc, $proc ) = @_;

    my ( $import_date ) = $db->query( "select import_date from solr_imports order by import_date desc limit 1" )->flat;

    $import_date //= '2000-01-01';

    INFO "importing delta from $import_date...";

    $db->query( <<END, $import_date );
create temporary table delta_import_stories as
select distinct stories_id
from story_sentences ss
where ss.db_row_last_updated > \$1 and MOD( stories_id, $num_proc ) = ( $proc - 1 )

END
    my ( $num_delta_stories ) = $db->query( "select count(*) from delta_import_stories" )->flat;
    INFO "found $num_delta_stories stories for import ...";

    _restrict_delta_import_stories_size( $db, $num_delta_stories );

    _add_extra_stories_to_import( $db, $import_date, $num_delta_stories, $num_proc, $proc );

}

# Get the $data_lookup hash that has lookup tables for values to include for each of the processed_stories, media_tags,
# stories_tags, and ss_tags fields for export to solr.
#
# This is basically just a manual client side join that we do in perl because we can get postgres to stream results much
# more quickly if we don't ask it to do this giant join on the server side.
sub _get_data_lookup
{
    my ( $db, $num_proc, $proc, $delta ) = @_;

    my $data_lookup = {};

    my $delta_clause = $delta ? 'and stories_id in ( select stories_id from delta_import_stories )' : '';

    _set_lookup( $db, $data_lookup, 'ps', <<END );
select processed_stories_id, stories_id
    from processed_stories
    where MOD(stories_id, $num_proc) = $proc - 1
        $delta_clause
END

    _set_lookup( $db, $data_lookup, 'media_tags', <<END );
select string_agg( tags_id::text, ';' ) tag_list, media_id
    from media_tags_map
    group by media_id
END
    _set_lookup( $db, $data_lookup, 'stories_tags', <<END );
select string_agg( tags_id::text, ';' ) tag_list, stories_id
    from stories_tags_map
    where MOD(stories_id, $num_proc) = $proc - 1
        $delta_clause
    group by stories_id
END

    _set_lookup( $db, $data_lookup, 'bitly_clicks', <<END );
select click_count, stories_id
    from bitly_clicks_total
    where MOD(stories_id, $num_proc) = $proc - 1
        $delta_clause
END

    _set_lookup( $db, $data_lookup, 'timespans', <<END );
select string_agg( timespans_id::text, ';' ), stories_id
    from snap.story_link_counts
    where MOD(stories_id, $num_proc) = $proc - 1
        $delta_clause
    group by stories_id
END

    return $data_lookup;
}

# Print a csv dump of the postgres data to $file. Run as job proc out of num_proc jobs, where each job is printg a
# separate set of data. If delta is true, only dump the data changed since the last dump
sub _print_csv_to_file_single_job
{
    my ( $db, $file, $num_proc, $proc, $delta ) = @_;

    # recreate db for forked processes
    $db ||= MediaWords::DB::connect_to_db;

    my $fh = FileHandle->new( ">$file" ) || die( "Unable to open file '$file': $@" );

    if ( $delta )
    {
        _create_delta_import_stories( $db, $num_proc, $proc );
    }

    my $stories_ids = $delta ? $db->query( "select * from delta_import_stories" )->flat : [];

    my $data_lookup = _get_data_lookup( $db, $num_proc, $proc, $delta );

    $db->begin;

    INFO "exporting sentences ...";
    _declare_sentences_cursor( $db, $delta, $num_proc, $proc );
    my $sentence_stories_ids = _print_csv_to_file_from_csr( $db, $fh, $data_lookup, 1 );

    INFO "exporting titles ...";
    _declare_titles_cursor( $db, $delta, $num_proc, $proc );
    my $title_stories_ids = _print_csv_to_file_from_csr( $db, $fh, $data_lookup, 0 );

    $db->commit;

    return $stories_ids;
}

=head2 print_csv_to_file( $db, $file_spec, $num_proc, $delta, $min_proc, $max_proc )

Print a csv dump of the postgres data for solr import. If delta is true, only dump the data changed since the last
dump.Run $num_proc jobs in parallel to generate the dump.

Returns a list of the dumped files and a list of all stories_ids dumped in this form:

    { files => $list_of_dump_files, stories_ids => $ids_dumps }

Assumes that $num_proc total jobs are being used to dump the data.  Fork off jobs to dump jobs $min_proc to $max_proc.
For example, to start 24 dump processes in three different machines, you would make the following calls:

    # on machine a
    print_csv_to_file( $db, $file_spec, 24, $delta, 1, 8 );

    # on machine b
    print_csv_to_file( $db, $file_spec, 24, $delta, 9, 16 );

    # on machine c
    print_csv_to_file( $db, $file_spec, 24, $delta, 17, 24 );

$num_proc, $min_proc, and $max_proc all default to 1.  $delta defaults to false.

Dump files are named ${ file_spec }-${ run_sig }-${ proc }.  For example, for a dump with $file_spec = 'solr.csv'
running as process 17, the file would be named 'solr.csv-csvBfxq-17'.

=cut

sub print_csv_to_file
{
    my ( $db, $file_spec, $num_proc, $delta, $min_proc, $max_proc ) = @_;

    $num_proc //= 1;
    $min_proc //= 1;
    $max_proc //= $num_proc;

    my $files;

    if ( $num_proc == 1 )
    {
        my $stories_ids = _print_csv_to_file_single_job( $db, $file_spec, 1, 1, $delta );

        return { files => [ $file_spec ], stories_ids => $stories_ids };
    }
    else
    {
        require forks;
        my $threads = [];

        for my $proc ( $min_proc .. $max_proc )
        {
            # every generated file should have a unique id so that the
            # file positioncaches don't get reused between imports
            my $file_id = Digest::MD5::md5_hex( "$$-" . time() );
            my $file    = "$file_spec-$file_id-$proc";

            push( @{ $files }, $file );

            push( @{ $threads },
                threads->create( \&_print_csv_to_file_single_job, undef, $file, $num_proc, $proc, $delta ) );
        }

        my $all_stories_ids = [];
        for my $thread ( @{ $threads } )
        {
            my $stories_ids = $thread->join();
            push( @{ $all_stories_ids }, @{ $stories_ids } );
        }

        return { files => $files, stories_ids => $all_stories_ids };
    }
}

# query solr for the given story_sentences_id and return true if the story_sentences_id already exists in solr
sub _sentence_exists_in_solr($$)
{
    my ( $story_sentences_id, $staging ) = @_;

    my $json;
    eval {
        my $params = { q => "story_sentences_id:$story_sentences_id", rows => 0, wt => 'json' };
        $json = _solr_request( 'select', $params, $staging );
    };
    if ( $@ )
    {
        my $error_message = $@;
        WARN "Unable to query Solr for story_sentences_id $story_sentences_id: $error_message";
        return 0;
    }

    my $data;
    eval { $data = MediaWords::Util::JSON::decode_json( $json ) };

    die( "Error parsing solr json: $@\n$json" ) if ( $@ );

    die( "Error received from solr: '$json'" ) if ( $data->{ error } );

    return $data->{ response }->{ numFound } ? 1 : 0;
}

# Send a request to MediaWords::Solr::get_solr_url. Return content on success, die() on error. If $staging is true, use
# the staging collection; otherwise use the live collection.
sub _solr_request($$$;$$)
{
    my ( $path, $params, $staging, $content, $content_type ) = @_;

    my $solr_url = MediaWords::Solr::get_solr_url;
    $params //= {};

    my $db = MediaWords::DB::connect_to_db;

    my $collection =
      $staging ? MediaWords::Solr::get_staging_collection( $db ) : MediaWords::Solr::get_live_collection( $db );

    my $abs_uri = URI->new( "$solr_url/$collection/$path" );
    $abs_uri->query_form( $params );
    my $abs_url = $abs_uri->as_string;

    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_max_size( undef );

    # should be able to process about this fast.  otherwise, time out and throw error so that we can continue processing
    my $req;

    my $timeout = 600;

    TRACE "Requesting URL: $abs_url...";

    if ( $content )
    {
        $content_type ||= 'text/plain; charset=utf-8';

        $req = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $abs_url );
        $req->set_header( 'Content-Type',   $content_type );
        $req->set_header( 'Content-Length', bytes::length( $content ) );
        $req->set_content( $content );
    }
    else
    {
        $req = MediaWords::Util::Web::UserAgent::Request->new( 'GET', $abs_url );
    }

    my $res;
    eval {
        local $SIG{ ALRM } = sub { die "alarm" };

        alarm $timeout;

        $ua->set_timeout( $timeout );
        $res = $ua->request( $req );

        alarm 0;
    };

    if ( $@ )
    {
        my $error_message = $@;

        if ( $error_message =~ /^alarm at/ )
        {
            die "Request to $abs_url timed out after $timeout seconds";
        }
        else
        {
            die "Request to $abs_url failed: $error_message";
        }
    }

    my $response = $res->decoded_content;
    unless ( $res->is_success )
    {
        die "Request to $abs_url returned HTTP error: $response";
    }

    return $response;
}

# return cache of the pos to read next from each file
sub _get_file_pos_cache
{
    my $mediacloud_data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

    return CHI->new(
        driver           => 'File',
        expires_in       => '1 year',
        expires_variance => '0.1',
        root_dir         => "${ mediacloud_data_dir }/cache/solr_import_file_pos",
        depth            => 4
    );
}

# get the file position to read next from the given file
sub _get_file_pos
{
    my ( $file ) = @_;

    my $abs_file = File::Spec->rel2abs( $file );

    my $cache = _get_file_pos_cache();

    return $cache->get( $abs_file ) || 0;
}

sub _set_file_pos
{
    my ( $file, $pos ) = @_;

    my $abs_file = File::Spec->rel2abs( $file );

    my $cache = _get_file_pos_cache();

    return $cache->set( $abs_file, $pos );
}

sub _get_file_errors_cache
{
    my ( $file ) = @_;

    my $abs_file = File::Spec->rel2abs( $file );

    my $mediacloud_data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

    return CHI->new(
        driver           => 'File',
        expires_in       => '1 year',
        expires_variance => '0.1',
        root_dir         => "${ mediacloud_data_dir }/cache/solr_import_file_errors/" . Digest::MD5::md5_hex( $abs_file ),
        depth            => 4
    );
}

# get a list of all errors for the file in the form { message => $error_message, pos => $pos }
sub _get_all_file_errors
{
    my ( $file ) = @_;

    my $cache = _get_file_errors_cache( $file );

    my $errors = $cache->dump_as_hash;

    return [ values( %{ $errors } ) ];
}

# add an error for the given file in the form { message => $error_message, pos => $pos }
sub _add_file_error
{
    my ( $file, $error ) = @_;

    my $cache = _get_file_errors_cache( $file );

    $cache->set( $error->{ pos }, $error );
}

# remove an error from the file
sub _remove_file_error
{
    my ( $file, $error ) = @_;

    my $cache = _get_file_errors_cache( $file );

    $cache->remove( $error->{ pos } );
}

# get chunk of $CSV_CHUNK_LINES csv lines from the csv file starting at _get_file_post. use _set_file_pos
# to advance the position pointer tot the next position in the file.  return undef if there is no more data
# to get from the file
sub _get_encoded_csv_data_chunk
{
    my ( $file, $single_pos ) = @_;

    my $fh = FileHandle->new;
    $fh->open( $file ) || die( "unable to open file '$file': $!" );

    flock( $fh, 2 ) || die( "Unable to lock file '$file': $!" );

    my $pos = defined( $single_pos ) ? $single_pos : _get_file_pos( $file );

    $fh->seek( $pos, 0 ) || die( "unable to seek to pos '$pos' in file '$file': $!" );

    my $csv_data;
    my $line;
    my $i = 0;

    my ( $first_story_sentences_id, $last_story_sentences_id );
    while ( ( $i < $CSV_CHUNK_LINES ) && ( $line = <$fh> ) )
    {
        # skip header line
        next if ( !$i && ( $line =~ /^[a-z_,]+$/ ) );

        next if ( !$i && $line !~ /^\d+\,/ );

        if ( !defined( $first_story_sentences_id ) )
        {
            $line =~ /^\d+\,\d+\,(\d+)\,/;
            $first_story_sentences_id = $1 || 0;
        }

        $csv_data .= $line;

        $i++;
    }

    $last_story_sentences_id = 0;
    $last_story_sentences_id = $1 if ( $line && ( $line =~ /^\d+\,\d+\,(\d+)\,/ ) );

    # find next valid csv record start, then backup to the beginning of that line
    while ( defined( $fh ) && ( $line = <$fh> ) && ( $line !~ /^\d+\,\d+\,\d+\,/ ) )
    {
        $csv_data .= $line;
    }
    $fh->seek( -1 * length( $line ), 1 ) if ( $line );

    if ( !$single_pos )
    {
        _set_file_pos( $file, $fh->tell );

        # this error gets removed once the chunk has been successfully processed so that
        # chunks in progress will get restarted if the process is killed
        _add_file_error( $file, { pos => $pos, message => 'in progress' } );
    }

    $fh->close || die( "Unable to close file '$file': $!" );

    return {
        csv                      => $csv_data,
        pos                      => $pos,
        first_story_sentences_id => $first_story_sentences_id,
        last_story_sentences_id  => $last_story_sentences_id
    };
}

# get the solr url and parameters to send csv data to
sub _get_import_url_params
{
    my ( $delta ) = @_;

    my $url_params = {
        'commit'                              => 'false',
        'header'                              => 'false',
        'fieldnames'                          => join( ',', @CSV_FIELDS ),
        'overwrite'                           => ( $delta ? 'true' : 'false' ),
        'f.tags_id_media.split'               => 'true',
        'f.tags_id_media.separator'           => ';',
        'f.tags_id_stories.split'             => 'true',
        'f.tags_id_stories.separator'         => ';',
        'f.tags_id_story_sentences.split'     => 'true',
        'f.tags_id_story_sentences.separator' => ';',
        'f.timespans_id.split'                => 'true',
        'f.timespans_id.separator'            => ';',
        'skip'                                => 'field_type,id,solr_import_date'
    };

    return ( 'update/csv', $url_params );
}

# print to STDERR a list of remaining errors on the given file
sub _print_file_errors
{
    my ( $file ) = @_;

    my $errors = _get_all_file_errors( $file );

    WARN "errors for file '$file':\n" . Dumper( $errors ) if ( @{ $errors } );

}

# find all error chunks saved for this file in the _file_errors_cache, and reprocess every error chunk
sub _reprocess_file_errors
{
    my ( $pm, $file, $staging ) = @_;

    my $delta = 1;
    my ( $import_url, $import_params ) = _get_import_url_params( $delta );

    my $errors = _get_all_file_errors( $file );

    INFO "reprocessing all errors for $file ...";

    for my $error ( @{ $errors } )
    {
        my $data = _get_encoded_csv_data_chunk( $file, $error->{ pos } );

        _remove_file_error( $file, { pos => $data->{ pos } } );

        next unless ( $data->{ csv } );

        INFO "reprocessing $file position $data->{ pos } ...";

        $pm->start and next if ( $pm->max_procs() > 1 );

        eval { _solr_request( $import_url, $import_params, $staging, $data->{ csv } ); };
        if ( $@ )
        {
            my $error = $@;
            _add_file_error( $file, { pos => $data->{ pos }, message => $error } );
        }

        $pm->finish if ( $pm->max_procs() > 1 );
    }

    $pm->wait_all_children if ( $pm->max_procs() > 1 );
}

# return the delta setting for the given chunk, which if true indicates that we cannot assume that
# all of the story_sentence_ids in the given chunk are not already in solr.
#
# we base this decision on lookups of the first ssid and the last ssid in the chunk:
# * if the last chunk_delta was 0, delta = 0 (run import with overwrite = false for rest of file)
# * if first ssid is not in solr, delta = 0 (run import with overwrite = false)
# * if the first ssid is in solr but the last is not, delta = 1 (run import with overwrite = true)
# * if the first ssid is in solr and the last ssid is in solr, delta = -1 (do not run import)
sub _get_chunk_delta($$$)
{
    my ( $chunk, $last_chunk_delta, $staging ) = @_;

    return 0 if ( defined( $last_chunk_delta ) && ( $last_chunk_delta == 0 ) );

    unless ( _sentence_exists_in_solr( $chunk->{ first_story_sentences_id }, $staging ) )
    {
        return 0;
    }

    unless ( _sentence_exists_in_solr( $chunk->{ last_story_sentences_id }, $staging ) )
    {
        return 1;
    }

    return -1;
}

# return true if the last sentence in the file is already present in solr, so we can skip this file
sub _last_sentence_in_solr($$)
{
    my ( $file, $staging ) = @_;

    my $bfh = File::ReadBackwards->new( $file ) || die( "Unable to open file '$file': $!" );

    my $last_story_sentences_id;
    while ( my $line = $bfh->readline )
    {
        if ( $line =~ /^\d+\,\d+\,(\d+)\,/ )
        {
            $last_story_sentences_id = $1;
            last;
        }
    }

    return 0 unless ( $last_story_sentences_id );

    return _sentence_exists_in_solr( $last_story_sentences_id, $staging );
}

# import a single csv dump file into solr using blocks
sub _import_csv_single_file
{
    my ( $file, $staging, $jobs ) = @_;

    my $pm = Parallel::ForkManager->new( $jobs );

    if ( _last_sentence_in_solr( $file, $staging ) )
    {
        INFO "skipping $file, last sentence already in solr";

        _reprocess_file_errors( $pm, $file, $staging );
        _print_file_errors( $file );

        return;
    }

    my $file_size = ( stat( $file ) )[ 7 ] || 1;

    my $start_time = time;
    my $start_pos;
    my $last_chunk_delta;
    my $chunk_num = 0;

    while ( my $data = _get_encoded_csv_data_chunk( $file ) )
    {
        $chunk_num++;
        last unless ( $data->{ csv } );

        $start_pos //= $data->{ pos };

        my $progress = int( $data->{ pos } * 100 / $file_size );
        my $partial_progress = ( ( $data->{ pos } + 1 ) - $start_pos ) / ( ( $file_size - $start_pos ) + 1 );

        my $elapsed_time = ( time + 1 ) - $start_time;

        my $remaining_time = int( $elapsed_time * ( 1 / $partial_progress ) ) - $elapsed_time;
        $remaining_time = 'unknown' if ( $chunk_num < $jobs );

        my $chunk_delta = _get_chunk_delta( $data, $last_chunk_delta, $staging );
        $last_chunk_delta = $chunk_delta;

        my $base_file = basename( $file );

        INFO
"importing $base_file position $data->{ pos } [ chunk $chunk_num, delta $chunk_delta, ${progress}%, $remaining_time secs left ] ...";

        if ( $chunk_delta < 0 )
        {
            _remove_file_error( $file, { pos => $data->{ pos } } );
            next;
        }

        $pm->start and next if ( $pm->max_procs() > 1 );

        my ( $import_url, $import_params ) = _get_import_url_params( $chunk_delta );

        eval { _solr_request( $import_url, $import_params, $staging, $data->{ csv } ); };
        my $error = $@;

        _remove_file_error( $file, { pos => $data->{ pos } } );
        if ( $error )
        {
            _add_file_error( $file, { pos => $data->{ pos }, message => $error } );
        }

        $pm->finish if ( $pm->max_procs() > 1 );
    }

    $pm->wait_all_children if ( $pm->max_procs() > 1 );

    _reprocess_file_errors( $pm, $file, $staging );

    _print_file_errors( $file );

    return 1;
}

=head2 import_csv_files( $files, $staging, $jobs )

Import existing csv files into solr.  Run $jobs processes in parallel to import each file (so $jobs processes to import
file 1, then $jobs processes to import file 2, etc).

Streams the csv data into the solr update/csv web service in chunks.

Keeps track of the import of each csv file between runs of the script by storing the last position of each chunk
processed by each file, by name.  If a given chunk causes an error during the import, records the error state
of that chunk and continues to the next chunk.  Retries processing all chunks that generated an error, and reports
which chunks continued to fail after reprocessing.

For each chunk, if the first sentence and the last sentence is already in solr, skip importing the chunk.  If the
first sentence but not the last sentence is in solr, assume that the sentences for that chunk may already be in
solr and import with the solr param overwrite=true.  If the first sentence is not solr, assume that we can run the
import with the solr param overwrite=false.

For the above logic to work, you must either be importing from scratch (delete entire solr database, generate full csv
dump, import csvs) or you must have deleted all sentences present in the import and committed that delete before running
this function (generate_and_import_data() below takes care to do this correctly).

=cut

sub import_csv_files($$$)
{
    my ( $files, $staging, $jobs ) = @_;

    $jobs ||= 1;

    for my $file ( @{ $files } )
    {
        _import_csv_single_file( $file, $staging, $jobs );
    }

    for my $file ( @{ $files } )
    {
        _print_file_errors( $file );
    }

    return 1;
}

# store in memory the current date according to postgres
sub _mark_import_date
{
    my ( $db ) = @_;

    ( $_import_date ) = $db->query( "select now()" )->flat;
}

# store the date marked by mark_import_date in solr_imports
sub _save_import_date
{
    my ( $db, $delta, $stories_ids ) = @_;

    die( "import date has not been marked" ) unless ( $_import_date );

    my $full_import = $delta ? 'f' : 't';
    $db->query( <<SQL, $_import_date, $full_import, scalar( @{ $stories_ids } ) );
insert into solr_imports( import_date, full_import, num_stories ) values ( ?, ?, ? )
SQL

}

# save log of all stories imported into solr
sub _save_import_log
{
    my ( $db, $stories_ids ) = @_;

    die( "import date has not been marked" ) unless ( $_import_date );

    $db->begin;
    for my $stories_id ( @{ $stories_ids } )
    {
        $db->query( <<SQL, $stories_id, $_import_date );
insert into solr_imported_stories ( stories_id, import_date ) values ( ?, ? )
SQL
    }
    $db->commit;
}

# given a list of stories_ids, return a stories_id:... solr query that replaces individual ids with ranges where
# possible.  Avoids >1MB queries that consists of lists of >100k stories_ids.
sub _get_stories_id_solr_query
{
    my ( $ids ) = @_;

    die( "empty stories_ids" ) unless ( @{ $ids } );

    $ids = [ sort { $a <=> $b } @{ $ids } ];

    my $singletons = [ -2 ];
    my $ranges = [ [ -2 ] ];
    for my $id ( @{ $ids } )
    {
        if ( $id == ( $ranges->[ -1 ]->[ -1 ] + 1 ) )
        {
            push( @{ $ranges->[ -1 ] }, $id );
        }
        elsif ( $id == ( $singletons->[ -1 ] + 1 ) )
        {
            push( @{ $ranges }, [ pop( @{ $singletons } ), $id ] );
        }
        else
        {
            push( @{ $singletons }, $id );
        }
    }

    shift( @{ $singletons } );
    shift( @{ $ranges } );

    my $long_ranges = [];
    for my $range ( @{ $ranges } )
    {
        if ( scalar( @{ $range } ) > 2 )
        {
            push( @{ $long_ranges }, $range );
        }
        else
        {
            push( @{ $singletons }, @{ $range } );
        }
    }

    my $queries = [];

    push( @{ $queries }, map { "stories_id:[$_->[ 0 ] TO $_->[ -1 ]]" } @{ $long_ranges } );
    push( @{ $queries }, 'stories_id:(' . join( ' ', @{ $singletons } ) . ')' ) if ( @{ $singletons } );

    my $query = join( ' ', @{ $queries } );

    return $query;
}

# delete the given stories from solr
sub delete_stories
{
    my ( $stories_ids, $staging, $jobs ) = @_;

    return 1 unless ( $stories_ids && scalar @{ $stories_ids } );

    INFO "deleting " . scalar( @{ $stories_ids } ) . " stories ...";

    $stories_ids = [ sort { $a <=> $b } @{ $stories_ids } ];

    my $max_chunk_size = 5000;

    while ( @{ $stories_ids } )
    {
        my $chunk_ids = [];
        my $chunk_size = List::Util::min( $max_chunk_size, scalar( @{ $stories_ids } ) );
        map { push( @{ $chunk_ids }, shift( @{ $stories_ids } ) ) } ( 1 .. $chunk_size );

        INFO "deleting chunk: " . scalar( @{ $chunk_ids } ) . " stories ...";

        my $stories_id_query = _get_stories_id_solr_query( $chunk_ids );

        my $delete_query = "<delete><query>$stories_id_query</query></delete>";

        eval { _solr_request( 'update', undef, $staging, $delete_query, 'application/xml' ); };
        if ( $@ )
        {
            my $error = $@;
            WARN "Error while deleting stories: $error";
            return 0;
        }
    }

    return 1;
}

# delete all stories from solr
sub delete_all_sentences
{
    my ( $staging ) = @_;

    INFO "deleting all sentences ...";

    my $url_params = { 'commit' => 'true', 'stream.body' => '<delete><query>*:*</query></delete>', };
    eval { _solr_request( 'update', $url_params, $staging ); };
    if ( $@ )
    {
        my $error = $@;
        WARN "Error while deleting all sentences: $error";
        return 0;
    }

    return 1;
}

# get a temp file name to for a delta dump
sub _get_dump_file
{
    my $data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

    my $dump_dir = "$data_dir/solr_dumps/dumps";

    MediaWords::Util::Paths::mkdir_p( $dump_dir ) unless ( -d $dump_dir );

    my ( $fh, $filename ) = File::Temp::tempfile( 'solr-delta.csvXXXX', DIR => $dump_dir );
    close( $fh );

    return $filename;
}

# delete stories that have just been imported from the media import queue
sub _delete_stories_from_import_queue
{
    my ( $db, $delta, $stories_ids ) = @_;

    INFO( "deleting stories from import queue ..." );

    if ( $delta )
    {
        return unless ( @{ $stories_ids } );

        my $stories_ids_list = join( ',', @{ $stories_ids } );

        $db->query(
            <<SQL
            DELETE FROM solr_import_extra_stories
            WHERE stories_id IN ($stories_ids_list)
SQL
        );
    }
    else
    {
        # if we just completed a full import, drop the whole current stories queue
        $db->query( 'TRUNCATE TABLE solr_import_extra_stories' );
    }
}

# guess whether this might be a production solr instance by just looking at the size.  this is useful so that we can
# cowardly refuse to delete all content from something that may be a production instance.
sub _maybe_production_solr
{
    my ( $db ) = @_;

    my $num_sentences = MediaWords::Solr::get_num_found( $db, { q => '*:*', rows => 0 } );

    die( "Unable to query solr for number of sentences" ) unless ( defined( $num_sentences ) );

    return ( $num_sentences > 100_000_000 );
}

# return true if there are less than 100k rows in solr_import_extra_stories
sub _stories_queue_is_small
{
    my ( $db ) = @_;

    my $exist = $db->query( "select 1 from solr_import_extra_stories offset 100000 limit 1" )->hash;

    return $exist ? 0 : 1;
}

# set snapshots.searchable to true for all snapshots that are currently false and
# have no stories in the solr_import_extra_stories queue
sub _update_snapshot_solr_status
{
    my ( $db ) = @_;

    # the combination the searchable clause and the not exists which stops after the first hit should
    # make this quite fast
    $db->query( <<SQL );
update snapshots s set searchable = true
    where
        searchable = false and
        not exists (
            select 1
                from timespans t
                    join snap.story_link_counts slc using ( timespans_id )
                    join solr_import_extra_stories sies using ( stories_id )
                where t.snapshots_id = s.snapshots_id
        )
SQL
}

=head2 generate_and_import_data( $delta, $delete, $staging, $jobs )

Generate and import dump.  If $delta is true, generate delta dump since beginning of last full or delta dump.  If $delta
is true, delete all solr data after generating dump and before importing.

Keep rerunning the function until there are less than 100k jobs left in the solr_import_extra_stories queue, or until
loop has run 100 times (the process has some memory leaks, so it should be restarted periodically).

Run $jobs parallel jobs for the csv dump and for the solr import.

=cut

sub generate_and_import_data
{
    my ( $delta, $delete, $staging, $jobs ) = @_;

    $jobs ||= 1;

    die( "cannot import with delta and delete both true" ) if ( $delta && $delete );

    my $db = MediaWords::DB::connect_to_db;

    die( "refusing to delete maybe production solr" ) if ( $delete && _maybe_production_solr( $db ) );

    my $i = 0;

    while ()
    {
        my $dump_file = _get_dump_file();

        _mark_import_date( $db );

        INFO "generating dump ...";
        my $dump = print_csv_to_file( $db, $dump_file, $jobs, $delta ) || die( "dump failed." );

        my $stories_ids = $dump->{ stories_ids };
        my $dump_files  = $dump->{ files };

        if ( $delta )
        {
            INFO "deleting updated stories ...";
            delete_stories( $stories_ids, $staging ) || die( "delete stories failed." );
        }
        elsif ( $delete )
        {
            INFO "deleting all stories ...";
            delete_all_sentences( $staging ) || die( "delete all sentences failed." );
        }

        _solr_request( 'update', { 'commit' => 'true' }, $staging );

        INFO "importing dump ...";
        import_csv_files( $dump_files, $staging, $jobs ) || die( "import failed." );

        # have to reconnect becaue import_csv_files may have forked, ruining existing db handles
        $db = MediaWords::DB::connect_to_db;

        _save_import_date( $db, $delta, $stories_ids );
        _save_import_log( $db, $stories_ids );
        _delete_stories_from_import_queue( $db, $delta, $stories_ids );

        # if we're doing a full import, do a delta to catchup with the data since the start of the import
        if ( !$delta )
        {
            generate_and_import_data( 1, 0, $staging );
        }

        INFO( "committing solr index changes ..." );
        _solr_request( 'update', { 'commit' => 'true' }, $staging );

        map { unlink( $_ ) } @{ $dump_files };

        _update_snapshot_solr_status( $db );

        last if ( _stories_queue_is_small( $db ) || ( ++$i > 100 ) );

        # the machine literally overheats if it does too many imports without a break
        if ( $i > 3 )
        {
            sleep( 300 );
        }
    }
}

1;
