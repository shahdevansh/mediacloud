package MediaWords::Controller::Api::V2::Topics::Stories;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Readonly;

use MediaWords::DBI::ApiLinks;
use MediaWords::Solr;
use MediaWords::TM::Snapshot;

Readonly my $DEFAULT_STORY_LIMIT => 10;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(
    action => {
        list     => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        facebook => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        count    => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub link_paging_key { return 'stories'; }

sub pre_deserialize($$)
{
    my ( $self, $c ) = @_;

    $c->stash->{ timespan } = MediaWords::TM::set_timespans_id_param( $c );
}

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;

    $c->stash->{ topics_id } = $topics_id;
}

sub stories : Chained('apibase') : PathPart('stories') : CaptureArgs(0)
{
}

sub list : Chained('stories') : Args(0) : ActionClass('MC_REST')
{
}

# get any where clauses for media_id, link_to_stories_id, link_from_stories_id, stories_id params
sub _get_extra_where_clause($$)
{
    my ( $c, $timespans_id ) = @_;

    my $clauses = [];

    if ( my $media_id = $c->req->params->{ media_id } )
    {
        my $media_ids = ref( $media_id ) ? $media_id : [ $media_id ];
        my $media_ids_list = join( ',', map { $_ += 0 } @{ $media_ids } );
        push( @{ $clauses }, "s.media_id in ( $media_ids_list )" );
    }

    if ( my $stories_id = $c->req->params->{ stories_id } )
    {
        my $stories_ids = ref( $stories_id ) ? $stories_id : [ $stories_id ];
        my $stories_ids_list = join( ',', map { $_ += 0 } @{ $stories_ids } );
        push( @{ $clauses }, "s.stories_id in ( $stories_ids_list )" );
    }

    if ( my $link_to_stories_id = $c->req->params->{ link_to_stories_id } )
    {
        $link_to_stories_id += 0;
        $timespans_id       += 0;
        push( @{ $clauses }, <<SQL );
s.stories_id in (
    select
            sl.source_stories_id
        from snap.story_links sl
        where
            sl.ref_stories_id = $link_to_stories_id and
            sl.timespans_id = $timespans_id
)
SQL

    }

    if ( my $link_from_stories_id = $c->req->params->{ link_from_stories_id } )
    {
        $link_from_stories_id += 0;
        $timespans_id         += 0;
        push( @{ $clauses }, <<SQL );
s.stories_id in (
    select
            sl.ref_stories_id
        from snap.story_links sl
        where
            sl.source_stories_id = $link_from_stories_id and
            sl.timespans_id = $timespans_id
)
SQL

    }

    if ( my $link_to_media_id = $c->req->params->{ link_to_media_id } )
    {
        $link_to_media_id += 0;
        $timespans_id     += 0;
        push( @{ $clauses }, <<SQL );
s.stories_id in (
    select
            sl.source_stories_id
        from snap.story_links sl
            join timespans t using ( timespans_id )
            join snap.stories s on ( sl.ref_stories_id = s.stories_id and s.snapshots_id = t.snapshots_id )
        where
            s.media_id = $link_to_media_id and
            sl.timespans_id = $timespans_id
)
SQL

    }

    if ( my $link_from_media_id = $c->req->params->{ link_from_media_id } )
    {
        $link_from_media_id += 0;
        $timespans_id       += 0;
        push( @{ $clauses }, <<SQL );
s.stories_id in (
    select
            sl.ref_stories_id
        from snap.story_links sl
            join timespans t using ( timespans_id )
            join snap.stories s on ( sl.source_stories_id = s.stories_id and s.snapshots_id = t.snapshots_id )
        where
            s.media_id = $link_from_media_id and
            sl.timespans_id = $timespans_id
)
SQL

    }

    if ( my $q = $c->req->params->{ q } )
    {
        $q = "timespans_id:$timespans_id and ( $q )";

        my $solr_stories_id = MediaWords::Solr::search_for_stories_ids( $c->dbis, { q => $q, rows => 10_000_000 } );

        $solr_stories_id = [ map { int( $_ ) } @{ $solr_stories_id } ];

        my $ids_table = $c->dbis->get_temporary_ids_table( $solr_stories_id );
        push( @{ $clauses }, "s.stories_id in ( select id from $ids_table )" );
    }

    return '' unless ( @{ $clauses } );

    return 'and ' . join( ' and ', map { "( $_ ) " } @{ $clauses } );
}

# add a foci list to each story that lists each focus to which the story belongs
sub _add_foci_to_stories($$$)
{
    my ( $db, $timespan, $stories ) = @_;

    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    my $foci = $db->query( <<SQL, $timespan->{ timespans_id } )->hashes;
select
        slc.stories_id,
        f.foci_id,
        f.name,
        fs.name focal_set_name
    from snap.story_link_counts slc
        join timespans a on ( a.timespans_id = slc.timespans_id )
        join timespans b on
            ( a.snapshots_id = b.snapshots_id and
                a.start_date = b.start_date and
                a.end_date = b.end_date and
                a.period = b.period )
        join foci f on ( f.foci_id = b.foci_id )
        join focal_sets fs on ( f.focal_sets_id = fs.focal_sets_id )
        join snap.story_link_counts slcb on
            ( slcb.stories_id = slc.stories_id and
                slcb.timespans_id = b.timespans_id )
    where
        slc.stories_id in ( select id from $ids_table ) and
        a.timespans_id = \$1
SQL

    MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $foci, 'foci' );
}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $timespan = MediaWords::TM::set_timespans_id_param( $c );

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    $c->req->params->{ sort }  ||= 'inlink';
    $c->req->params->{ limit } ||= 1000;

    my $sort_param = $c->req->params->{ sort };

    # md5 hashing is to make tie breaks random but consistent
    my $sort_clause =
      ( $sort_param eq 'social' )
      ? 'slc.bitly_click_count desc nulls last, md5( s.stories_id::text )'
      : 'slc.media_inlink_count desc, md5( s.stories_id::text )';

    my $timespans_id = $timespan->{ timespans_id };
    my $snapshots_id = $timespan->{ snapshots_id };

    my $extra_clause = _get_extra_where_clause( $c, $timespans_id );

    my $limit  = $c->req->params->{ limit };
    my $offset = $c->req->params->{ offset };

    my $stories = $db->query( <<SQL, $timespans_id, $snapshots_id, $limit, $offset )->hashes;
select s.*, slc.*, m.name media_name
    from snap.story_link_counts slc
        join snap.stories s on slc.stories_id = s.stories_id
        join snap.media m on s.media_id = m.media_id
    where slc.timespans_id = \$1
        and s.snapshots_id = \$2
        and m.snapshots_id = \$2
        $extra_clause
    order by $sort_clause
    limit \$3 offset \$4
SQL

    _add_foci_to_stories( $db, $timespan, $stories );

    MediaWords::DBI::Stories::GuessDate::add_date_is_reliable_to_stories( $db, $stories );

    MediaWords::DBI::Stories::GuessDate::add_undateable_to_stories( $db, $stories );
    map { $_->{ publish_date } = 'undateable' if ( $_->{ undateable } ); delete( $_->{ undateable } ) } @{ $stories };

    map { $_->{ stories_id } = int( $_->{ stories_id } ) } @{ $stories };

    my $entity = { stories => $stories };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'stories' );

    $self->status_ok( $c, entity => $entity );

}

sub facebook : Chained('stories') : Args(0) : ActionClass('MC_REST')
{
}

sub facebook_GET
{
    my ( $self, $c ) = @_;

    my $timespan = MediaWords::TM::set_timespans_id_param( $c );

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    $c->req->params->{ limit } ||= 1000;

    my $timespans_id = $timespan->{ timespans_id };

    my $limit  = $c->req->params->{ limit };
    my $offset = $c->req->params->{ offset };

    my $counts = $db->query( <<SQL, $timespans_id, $limit, $offset )->hashes;
select
        ss.stories_id,
        ss.facebook_share_count,
        ss.facebook_comment_count,
        ss.facebook_api_collect_date
    from snap.story_link_counts slc
        join story_statistics ss using ( stories_id )
    where slc.timespans_id = \$1
    order by ss.stories_id
    limit \$2 offset \$3
SQL

    my $entity = { counts => $counts };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'counts' );

    $self->status_ok( $c, entity => $entity );

}

sub count : Chained('stories') : Args(0) : ActionClass('MC_REST')
{
}

sub count_GET
{
    my ( $self, $c ) = @_;

    my $timespan     = MediaWords::TM::set_timespans_id_param( $c );
    my $timespans_id = $timespan->{ timespans_id };

    my $db = $c->dbis;

    my $q = $c->req->params->{ q };

    if ( $q )
    {
        $c->req->params->{ q } = "timespans_id:$timespans_id and ( $q )";
        return $c->controller( 'Api::V2::Stories_Public' )->count_GET( $c );
    }
    else
    {
        my ( $n ) =
          $db->query( "select count(*) from snap.story_link_counts where timespans_id = \$1", $timespans_id )->flat;
        $self->status_ok( $c, entity => { count => $n } );
    }
}

1;
