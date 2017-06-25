package MediaWords::Controller::Api::V2::Topics::Media;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;

use MediaWords::DBI::ApiLinks;
use MediaWords::Solr;
use MediaWords::TM::Snapshot;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(
    action => {
        list => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        map  => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;
    $c->stash->{ topics_id } = int( $topics_id );
}

sub media : Chained('apibase') : PathPart('media') : CaptureArgs(0)
{

}

sub list : Chained('media') : Args(0) : ActionClass('MC_REST')
{

}

# get any where clauses for media_id, link_to_stories_id, link_from_stories_id, stories_id params
sub _get_extra_where_clause($$)
{
    my ( $c, $timespans_id ) = @_;

    my $clauses = [];

    if ( my $media_id = $c->req->params->{ media_id } )
    {
        $media_id += 0;
        push( @{ $clauses }, "m.media_id = $media_id" );
    }

    if ( my $name = $c->req->params->{ name } )
    {
        if ( length( $name ) < 3 )
        {
            push( @{ $clauses }, "false" );
        }
        else
        {
            my $q_name_val = $c->dbis->quote( '%' . $name . '%' );
            push( @{ $clauses }, "m.name ilike $q_name_val" );
        }
    }

    return '' unless ( @{ $clauses } );

    return 'and ' . join( ' and ', map { "( $_ ) " } @{ $clauses } );
}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $timespan = MediaWords::TM::set_timespans_id_param( $c );

    MediaWords::DBI::ApiLinks::process_and_stash_link( $c );

    my $db = $c->dbis;

    my $sort_param = $c->req->params->{ sort } || 'inlink';

    # md5 hashing is to make tie breaks random but consistent
    my $sort_clause =
      ( $sort_param eq 'social' )
      ? 'mlc.bitly_click_count desc nulls last, md5( m.media_id::text )'
      : 'mlc.media_inlink_count desc, md5( m.media_id::text )';

    my $timespans_id = $timespan->{ timespans_id };
    my $snapshots_id = $timespan->{ snapshots_id };

    my $limit  = $c->req->params->{ limit };
    my $offset = $c->req->params->{ offset };

    my $extra_clause = _get_extra_where_clause( $c, $timespans_id );

    my $media = $db->query( <<SQL, $timespans_id, $snapshots_id, $limit, $offset )->hashes;
select *
    from snap.medium_link_counts mlc
        join snap.media m on mlc.media_id = m.media_id
    where mlc.timespans_id = \$1 and
        m.snapshots_id = \$2
        $extra_clause
    order by $sort_clause
    limit \$3 offset \$4

SQL

    my $entity = { media => $media };

    MediaWords::DBI::ApiLinks::add_links_to_entity( $c, $entity, 'media' );

    $self->status_ok( $c, entity => $entity );
}

sub map : Chained('media') : Args(0) : ActionClass('MC_REST')
{

}

sub map_GET
{
    my ( $self, $c ) = @_;

    my $timespan             = MediaWords::TM::set_timespans_id_param( $c );
    my $color_field          = $c->req->params->{ color_field } || 'media_type';
    my $num_media            = $c->req->params->{ num_media } || 500;
    my $include_weights      = $c->req->params->{ include_weights } || 0;
    my $num_links_per_medium = $c->req->params->{ num_links_per_medium } || 1000;
    my $exclude_media_ids    = $c->req->params->{ exclude_media_ids } || [];

    $exclude_media_ids = [ $exclude_media_ids ] unless ( ref( $exclude_media_ids ) eq ref( [] ) );

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', int( $c->stash->{ topics_id } ) );

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic );

    my $gexf_options = {
        max_media            => $num_media,
        color_field          => $color_field,
        include_weights      => $include_weights,
        max_links_per_medium => $num_links_per_medium,
        exclude_media_ids    => $exclude_media_ids
    };
    my $gexf = MediaWords::TM::Snapshot::get_gexf_snapshot( $db, $timespan, $gexf_options );

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

    my $base_url = $c->uri_for( '/' );

    $gexf =~ s/\[_mc_base_url_\]/$base_url/g;

    my $file = "media_$timespan->{ timespans_id }.gexf";

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/gexf; charset=UTF-8' );
    $c->response->content_length( bytes::length( $gexf ) );
    $c->response->body( $gexf );
}

1;
