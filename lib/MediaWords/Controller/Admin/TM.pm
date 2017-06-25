package MediaWords::Controller::Admin::TM;

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Activities;
use MediaWords::DBI::Media;
use MediaWords::DBI::Stories::GuessDate;
use MediaWords::DBI::Stories;
use MediaWords::Job::TM::MineTopic;
use MediaWords::Solr;
use MediaWords::Solr::Query;
use MediaWords::Solr::WordCounts;
use MediaWords::TM::Mine;
use MediaWords::TM::Snapshot;
use MediaWords::TM;
use MediaWords::Util::Bitly;
use MediaWords::Util::JSON;

use Digest::MD5;
use List::Compare;
use Readonly;

Readonly my $ROWS_PER_PAGE => 25;

use base 'Catalyst::Controller::HTML::FormFu';

sub index : Path : Args(0)
{
    return list( @_ );
}

# list all topics
sub list : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics = $db->query( <<END )->hashes;
select c.*
    from topics c
        left join snapshots snap on ( c.topics_id = snap.topics_id )
    group by c.topics_id
    order by c.state = 'completed', max( coalesce( snap.snapshot_date, '2000-01-01'::date ) ) desc
END

    $c->stash->{ topics }   = $topics;
    $c->stash->{ template } = 'tm/list.tt2';
}

sub _add_topic_date
{
    my ( $db, $topic, $start_date, $end_date ) = @_;

    my $existing_date = $db->query( <<END, $start_date, $end_date, $topic->{ topics_id } )->hash;
select * from topic_dates where start_date = ? and end_date = ? and topics_id = ?
END

    if ( !$existing_date )
    {
        $db->create(
            'topic_dates',
            {
                topics_id  => $topic->{ topics_id },
                start_date => $start_date,
                end_date   => $end_date
            }
        );
    }

}

# edit an existing topic
sub edit : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $form = $c->create_form( { load_config_file => $c->path_to() . '/root/forms/admin/tm/create_topic.yml' } );

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', $topics_id );

    $form->default_values( $topic );
    $form->process( $c->req );

    if ( !$form->submitted_and_valid )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ topic }    = $topic;
        $c->stash->{ template } = 'tm/edit_topic.tt2';
        return;
    }

    my $p = $form->params;

    my $num_stories = eval { MediaWords::Solr::count_stories( $db, { q => $p->{ solr_seed_query } } ) };
    die( "invalid solr query: $@" ) if ( $@ );

    die( "number of stories from query ($num_stories) is more than the max (500,000)" ) if ( $num_stories > 500000 );

    my $pattern;
    if ( $p->{ solr_seed_query } eq $topic->{ solr_seed_query } )
    {
        $pattern = $topic->{ pattern };
    }
    else
    {
        $pattern = eval { MediaWords::Solr::Query::parse( $p->{ solr_seed_query } )->re() };
        die( "unable to translate solr query to topic pattern: $@" ) if ( $@ );
    }

    if ( $p->{ preview } )
    {
        my $solr_seed_query = $p->{ solr_seed_query };
        $c->res->redirect( $c->uri_for( '/search', { q => $solr_seed_query, pattern => $pattern } ) );
        return;
    }

    else
    {
        delete( $p->{ preview } );

        $p->{ solr_seed_query_run } = 'f' unless ( $topic->{ solr_seed_query } eq $p->{ solr_seed_query } );
        $p->{ pattern } = $pattern;

        $p->{ solr_seed_query_run } = normalize_boolean_for_db( $p->{ solr_seed_query_run } );

        $c->dbis->update_by_id( 'topics', $topics_id, $p );

        my $view_url = $c->uri_for( "/admin/tm/view/" . $topics_id, { status_msg => 'topic updated.' } );
        $c->res->redirect( $view_url );

        return;
    }
}

# parse solr_seed_query coming directy from dashboard export.  return the part of the query without the
# date or media source clauses as well as the list of media tags_ids from the filtered part of the query.
# die if the query is not the form exported by the dashboard tool.  this is pretty kludgy but is just intended
# to get us through the couple of weeks until we have topic editing in the new web tool
sub _parse_solr_seed_query($)
{
    my ( $full_query ) = @_;

# sample dashboard exported query:
# +( "media cloud" mediacloud ) AND (+publish_date:[2016-01-01T00:00:00Z TO 2017-01-26T23:59:59Z]) AND ((tags_id_media:8875027 OR tags_id_stories:8875027))
    if ( $full_query !~ /(.*) AND \(\+publish_date\:\[.*\]\) AND \(\((tags_id_media.*)\)\)$/ )
    {
        die( "unable to parse solr query (query must be in exact form exported by dashboard): '$full_query'" );
    }

    my ( $filtered_query, $tags_list ) = ( $1, $2 );

    my $tags_ids_lookup = {};
    while ( $tags_list =~ /(\d+)/g )
    {
        $tags_ids_lookup->{ $1 } = 1;
    }

    my $tags_ids = [ keys( %{ $tags_ids_lookup } ) ];

    return ( $filtered_query, $tags_ids );
}

# create a new topic
sub create : Local
{
    my ( $self, $c ) = @_;

    my $form = $c->create_form( { load_config_file => $c->path_to() . '/root/forms/admin/tm/create_topic.yml' } );

    my $db = $c->dbis;

    $c->stash->{ form }     = $form;
    $c->stash->{ template } = 'tm/create_topic.tt2';

    # if ( defined ( $c->req->params->{ pattern } ) )
    # {
    # 	utf8::encode( $c->req->params->{ pattern } );
    # }

    # if ( defined ( $c->req->params->{ solr_seed_query } ) )
    # {
    # 	utf8::encode( $c->req->params->{ solr_seed_query } );
    # }

    $form->process( $c->request );

    if ( !$form->submitted_and_valid )
    {
        # Just show the form
        return;
    }

    # At this point the form is submitted

    my $c_name            = $c->req->params->{ name };
    my $c_solr_seed_query = $c->req->params->{ solr_seed_query };
    my $c_skip_solr_query = normalize_boolean_for_db( $c->req->params->{ skip_solr_query } );
    my $c_description     = $c->req->params->{ description };
    my $c_start_date      = $c->req->params->{ start_date };
    my $c_end_date        = $c->req->params->{ end_date };
    my $c_max_iterations  = $c->req->params->{ max_iterations };

    my $num_stories = eval { MediaWords::Solr::count_stories( $db, { q => $c_solr_seed_query } ) };
    die( "invalid solr query: $@" ) if ( $@ );

    die( "number of stories from query ($num_stories) is more than the max (500,000)" ) if ( $num_stories > 500000 );

    my $pattern = eval { MediaWords::Solr::Query::parse( $c_solr_seed_query )->re() };
    die( "unable to translate solr query to topic pattern: $@" ) if ( $@ );

    if ( $c->req->params->{ preview } )
    {
        $c->res->redirect( $c->uri_for( '/search', { q => $c_solr_seed_query, pattern => $pattern } ) );
        return;
    }

    my ( $filtered_seed_query, $tags_ids ) = _parse_solr_seed_query( $c_solr_seed_query );

    $db->begin;

    my $topic = $db->create(
        'topics',
        {
            name                => $c_name,
            pattern             => $pattern,
            solr_seed_query     => $filtered_seed_query,
            solr_seed_query_run => normalize_boolean_for_db( $c_skip_solr_query ),
            description         => $c_description,
            max_iterations      => $c_max_iterations,
            start_date          => $c_start_date,
            end_date            => $c_end_date,
            job_queue           => 'mc',
            max_stories         => 200_000
        }
    );

    for my $tags_id ( @{ $tags_ids } )
    {
        $db->query( <<SQL, $topic->{ topics_id }, $tags_id );
insert into topics_media_tags_map ( topics_id, tags_id ) values ( ?, ? )
SQL
    }

    $db->commit;

    my $status_msg = "Topic has been created.";
    $c->res->redirect( $c->uri_for( "/admin/tm/view/$topic->{ topics_id }", { status_msg => $status_msg } ) );
}

# get all timespans associated with a snapshot, sorted consistenty and
# with a tag_name field added
sub _get_timespan_from_cd
{
    my ( $db, $cd, $qs_id ) = @_;

    my $qs_clause = ( $qs_id ) ? "foci_id = $qs_id" : 'foci_id is null';

    my $timespans = $db->query( <<SQL, $cd->{ snapshots_id } )->hashes;
select timespan.*, coalesce( t.tag, '(all stories/no tag)' ) tag_name
    from
        timespans timespan
        left join tags t on ( timespan.tags_id = t.tags_id )
    where
        snapshots_id = ? and
        $qs_clause
    order by timespan.tags_id desc, period, start_date, end_date
SQL

    return $timespans;

}

# if there are pending topic_links, return a hash describing the status
# of the mining process with the following fields: stories_by_iteration, recent_topic_spider_metrics
sub _get_mining_status
{
    my ( $db, $topic ) = @_;

    my $cid = $topic->{ topics_id };

    my $stories_by_iteration = $db->query( <<END, $cid )->hashes;
select iteration, count(*) count
    from topic_stories
    where topics_id = ?
    group by iteration
    order by iteration asc
END

    my $recent_topic_spider_metrics = $db->query( <<SQL, $cid )->hashes;
select * from topic_spider_metrics where topics_id = ? order by topic_spider_metrics desc limit 25
SQL

    return {
        stories_by_iteration        => $stories_by_iteration,
        recent_topic_spider_metrics => $recent_topic_spider_metrics
    };
}

# get the topic snapshots associated with the given topic and optional focus.  attach
# periods label to each snapshot.
sub _get_snapshots($$$)
{
    my ( $db, $topic, $foci_id ) = @_;

    my $focus_clause = '';
    if ( $foci_id )
    {
        $focus_clause = <<SQL
and exists (
    select 1 from timespans timespan
    where timespan.foci_id = $foci_id and
        timespan.snapshots_id = snap.snapshots_id
)
SQL
    }

    my $snapshots = $db->query( <<SQL, $topic->{ topics_id } )->hashes;
select *
from snapshots snap
where snap.topics_id = ? $focus_clause
order by snapshots_id desc
SQL

    return $snapshots;
}

# get a list of the latest activities
sub _get_latest_activities
{
    my ( $db, $topics_id ) = @_;

    # Latest activities
    my Readonly $LATEST_ACTIVITIES_COUNT = 20;

    # Latest activities which directly or indirectly reference "topics.topics_id" = $topics_id
    my $sql_latest_activities =
      MediaWords::DBI::Activities::sql_activities_which_reference_column( 'topics.topics_id', $topics_id );

    $sql_latest_activities .= ' LIMIT ?';

    my $activities = $db->query( $sql_latest_activities, $LATEST_ACTIVITIES_COUNT )->hashes;

    # get activity descriptions
    map { $_->{ activity } = MediaWords::DBI::Activities::activity( $_->{ name } ) } @{ $activities };

    return $activities;
}

# get the topic with the given id, attach the focus associated with
# the foci_id, if any
sub _get_topic_with_focus
{
    my ( $db, $topics_id, $foci_id ) = @_;

    my $topic = $db->require_by_id( 'topics', $topics_id );

    if ( $foci_id )
    {
        $topic->{ focus } = $db->find_by_id( 'foci', $foci_id );
    }

    return $topic;
}

# view the details of a single topic
sub view : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $foci_id = $c->req->params->{ qs };

    my $db = $c->dbis;

    my $topic = _get_topic_with_focus( $db, $topics_id, $foci_id );

    my $snapshots = _get_snapshots( $db, $topic, $foci_id );

    my $focus_definitions = _get_focus_definitions( $db, $topic );

    $c->stash->{ topic }             = $topic;
    $c->stash->{ snapshots }         = $snapshots;
    $c->stash->{ focus_definitions } = $focus_definitions;
    $c->stash->{ template }          = 'tm/view.tt2';
}

# add num_stories, num_story_links, num_media, and num_media_links
# fields to the timespan
sub _add_media_and_story_counts_to_timespan
{
    my ( $db, $timespan ) = @_;

    ( $timespan->{ num_stories } ) = $db->query( "select count(*) from snapshot_story_link_counts" )->flat;

    ( $timespan->{ num_story_links } ) = $db->query( "select count(*) from snapshot_story_links" )->flat;

    ( $timespan->{ num_media } ) = $db->query( "select count(*) from snapshot_medium_link_counts" )->flat;

    ( $timespan->{ num_medium_links } ) = $db->query( "select count(*) from snapshot_medium_links" )->flat;
}

# get all foci in the given snapshot
sub _get_snapshot_foci
{
    my ( $db, $snapshot ) = @_;

    my $foci = $db->query( <<SQL, $snapshot->{ snapshots_id } )->hashes;
select f.*
    from foci f
        join focal_sets fs using ( focal_sets_id )
    where
        fs.snapshots_id = \$1
    order by f.name
SQL

    return $foci;
}

# view a topic snapshot, with a list of its timespans
sub view_snapshot : Local
{
    my ( $self, $c, $snapshots_id ) = @_;

    my $foci_id = $c->req->params->{ qs };

    my $db = $c->dbis;

    my $snapshot = $db->require_by_id( 'snapshots', $snapshots_id );

    my $topic = _get_topic_with_focus( $db, $snapshot->{ topics_id }, $foci_id );

    my $timespans = _get_timespan_from_cd( $db, $snapshot, $foci_id );

    map { _add_timespan_model_reliability( $db, $_ ) } @{ $timespans };

    my $foci = _get_snapshot_foci( $db, $snapshot );

    $c->stash->{ snapshot }  = $snapshot;
    $c->stash->{ topic }     = $topic;
    $c->stash->{ timespans } = $timespans;
    $c->stash->{ foci }      = $foci;
    $c->stash->{ template }  = 'tm/view_snapshot.tt2';
}

# generate a list of the top media for each of the timespans
sub _get_media_with_timespan_counts
{
    my ( $db, $cd ) = @_;

    # do this in one big complex quey because it's much faster than doing one for each timespan.
    # sort by media_inlink_count with each topic and keep only the 10 lowest ranked
    # media for each timespan.
    my $top_media = $db->query( <<END, $cd->{ snapshots_id } )->hashes;
with ranked_media as (
    select m.name as name,
            m.url as medium_url,
            mlc.media_id,
            mlc.timespans_id,
            timespan.model_num_media,
            timespan.start_date,
            mlc.media_inlink_count,
            rank() over w as media_inlink_count_rank,
            row_number() over w as media_inlink_count_row_number
        from timespans timespan
            join snapshots snap on ( timespan.snapshots_id = snap.snapshots_id )
            join snap.medium_link_counts mlc on ( timespan.timespans_id = mlc.timespans_id )
            join snap.media m on ( mlc.media_id = m.media_id and snap.snapshots_id = m.snapshots_id )
        where
            snap.snapshots_id = \$1 and
            timespan.period = 'weekly' and
            mlc.media_inlink_count > 1
        window w as (
            partition by mlc.timespans_id
                order by mlc.media_inlink_count desc )
)

select *
    from
        ranked_media
    where
        media_inlink_count_row_number <= 10 and
        media_inlink_count_row_number <= model_num_media

    order by start_date asc, media_inlink_count_rank asc, media_id asc
END

    my $top_media_lookup = {};
    my $all_dates_lookup = {};
    for my $top_medium ( @{ $top_media } )
    {
        my $d = substr( $top_medium->{ start_date }, 0, 10 );
        $all_dates_lookup->{ $d } = 1;

        my $m = $top_media_lookup->{ $top_medium->{ media_id } } ||= $top_medium;

        $m->{ first_date } ||= $d;
        $m->{ first_rank } ||= $top_medium->{ media_inlink_count_rank };

        $m->{ count_lookup }->{ $d } =
          [ $top_medium->{ media_inlink_count_rank }, $top_medium->{ timespans_id } ];
        $m->{ total_weight } += 100 / $top_medium->{ media_inlink_count_rank };
    }

    my $sorted_media =
      [ sort { ( $a->{ first_date } cmp $b->{ first_date } ) || ( $a->{ first_rank } <=> $b->{ first_rank } ) }
          values( %{ $top_media_lookup } ) ];

    my $all_dates = [ sort { $a cmp $b } keys %{ $all_dates_lookup } ];

    for my $medium ( @{ $sorted_media } )
    {
        $medium->{ counts } = [];
        for my $d ( @{ $all_dates } )
        {
            my $count = $medium->{ count_lookup }->{ $d } || [ 0, 0 ];
            push( @{ $medium->{ counts } }, [ $d, @{ $count } ] );
        }
    }

    return $sorted_media;
}

# generate a JSON of the weekly counts for any medium in the top
# ten media in any week
sub view_snapshot_media_over_time_json : Local
{
    my ( $self, $c, $snapshots_id ) = @_;

    my $db = $c->dbis;

    my $snapshot = $db->query( <<END, $snapshots_id )->hash;
select * from snapshots where snapshots_id = ?
END
    my $topic = $db->find_by_id( 'topics', $snapshot->{ topics_id } );

    my $media_with_timespan_counts = _get_media_with_timespan_counts( $db, $snapshot );

    $c->res->body( MediaWords::Util::JSON::encode_json( $media_with_timespan_counts ) );
}

# display network viz
sub nv : Local
{
    my ( $self, $c ) = @_;

    my $live         = $c->req->params->{ l };
    my $timespans_id = $c->req->params->{ timespan };
    my $color_field  = $c->req->params->{ cf };
    my $num_media    = $c->req->params->{ nm };

    my $db = $c->dbis;

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $timespans_id );

    $c->stash->{ timespan }    = $timespan;
    $c->stash->{ snapshot }    = $cd;
    $c->stash->{ topic }       = $topic;
    $c->stash->{ live }        = $live;
    $c->stash->{ color_field } = $color_field;
    $c->stash->{ num_media }   = $num_media;
    $c->stash->{ template }    = 'nv/nv.tt2';
}

# get JSON config file for network visualization.
# nv implemented in root/nv from the gephi sigma export template
sub nv_config : Local
{
    my ( $self, $c, $timespans_id, $live, $color_field, $num_media ) = @_;

    my $db = $c->dbis;

    $color_field ||= 'media_type';

    $live ||= '';

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $timespans_id );

    my $gexf_url = $c->uri_for(
        '/admin/tm/gexf/' . $timespan->{ timespans_id },
        {
            l  => $live,
            cf => $color_field,
            nm => $num_media
        }
      ) .
      '';

    my $config_data = {
        "type"    => "network",
        "version" => "1.0",
        "data"    => $gexf_url,
        "logo"    => {
            "text" => "",
            "file" => "",
            "link" => ""
        },
        "text" => {
            "title" => "",
            "more"  => "",
            "intro" => ""
        },
        "legend" => {
            "edgeLabel"  => "",
            "colorLabel" => "",
            "nodeLabel"  => ""
        },
        "features" => {
            "search"                 => JSON::true,
            "groupSelectorAttribute" => $color_field,
            "hoverBehavior"          => "dim"
        },
        "informationPanel" => {
            "imageAttribute"       => JSON::false,
            "groupByEdgeDirection" => JSON::true
        },
        "sigma" => {
            "graphProperties" => {
                "minEdgeSize" => 0.1,
                "maxNodeSize" => 15,
                "maxEdgeSize" => 0.1,
                "minNodeSize" => 0.5
            },
            "drawingProperties" => {
                "labelThreshold"           => 10,
                "hoverFontStyle"           => "bold",
                "defaultEdgeType"          => "curve",
                "defaultLabelColor"        => "#000",
                "defaultLabelHoverColor"   => "#fff",
                "defaultLabelSize"         => 14,
                "activeFontStyle"          => "bold",
                "fontStyle"                => "bold",
                "defaultHoverLabelBGColor" => "#002147",
                "defaultLabelBGColor"      => "#ddd"
            },
            "mouseProperties" => {
                "minRatio" => 0.75,
                "maxRatio" => 20
            }
        }
    };

    my $config_json = MediaWords::Util::JSON::encode_json( $config_data, 1, 1 );

    $c->response->content_type( 'application/json; charset=UTF-8' );
    $c->response->content_length( bytes::length( $config_json ) );
    $c->res->body( $config_json );
}

# generate the d3 chart of the weekly counts for any medium in the top
# ten media in any week
sub mot : Local
{
    my ( $self, $c, $snapshots_id ) = @_;

    my $db = $c->dbis;

    my $snapshot = $db->query( <<END, $snapshots_id )->hash;
select * from snapshots where snapshots_id = ?
END
    my $topic = $db->find_by_id( 'topics', $snapshot->{ topics_id } );

    $c->stash->{ topic }    = $topic;
    $c->stash->{ snapshot } = $snapshot;
    $c->stash->{ template } = 'tm/mot/mot.tt2';
}

# get the media marked as the most influential media for the current timespan
sub _get_top_media_for_timespan
{
    my ( $db, $timespan ) = @_;

    my $num_media = $timespan->{ model_num_media };

    return unless ( $num_media );

    $num_media = 20 if ( $num_media > 20 );

    my $top_media = $db->query(
        <<SQL,
        SELECT m.*,
              mlc.media_inlink_count,
              mlc.inlink_count,
               mlc.outlink_count,
               mlc.story_count,
               mlc.simple_tweet_count,
               mlc.normalized_tweet_count,
               mlc.bitly_click_count
        FROM snapshot_media_with_types AS m,
             snapshot_medium_link_counts AS mlc
        WHERE m.media_id = mlc.media_id
        ORDER BY mlc.media_inlink_count DESC
        LIMIT ?
SQL
        $num_media
    )->hashes;

    return $top_media;
}

# get the top 20 stories for the current timespan
sub _get_top_stories_for_timespan
{
    my ( $db ) = @_;

    my $top_stories = $db->query(
        <<END,
with top_story_link_counts as (
    select * from snapshot_story_link_counts order by media_inlink_count desc limit \$1
)

SELECT s.*,
       slc.media_inlink_count,
       slc.inlink_count,
       slc.outlink_count,
       slc.simple_tweet_count,
       slc.normalized_tweet_count,
       slc.bitly_click_count,
       m.name as medium_name,
       m.media_type
FROM snapshot_stories AS s,
     top_story_link_counts AS slc,
     snapshot_media_with_types AS m
WHERE s.stories_id = slc.stories_id
  AND s.media_id = m.media_id
ORDER BY slc.media_inlink_count DESC
END
        20
    )->hashes;

    MediaWords::DBI::Stories::GuessDate::add_date_is_reliable_to_stories( $db, $top_stories );
    MediaWords::DBI::Stories::GuessDate::add_undateable_to_stories( $db, $top_stories );

    return $top_stories;
}

# given the model r2 mean and sd values, return a string indicating whether the
# timespan is reliable, somewhat reliable, or not reliable
sub _add_timespan_model_reliability
{
    my ( $db, $timespan ) = @_;

    my $r2_mean   = $timespan->{ model_r2_mean }   || 0;
    my $r2_stddev = $timespan->{ model_r2_stddev } || 0;

    # compute the lowest standard reliability among the model runs
    my $lsr = $r2_mean - $r2_stddev;

    my $reliability;
    if ( $lsr > 0.85 )
    {
        $reliability = 'reliable';
    }
    elsif ( $lsr > 0.75 )
    {
        $reliability = 'somewhat';
    }
    else
    {
        $reliability = 'not';
    }

    $timespan->{ model_reliability } = $reliability;
}

# get the timespan, snapshot, and topic for the current request
sub _get_topic_objects
{
    my ( $db, $timespans_id ) = @_;

    die( "timespan param is required" ) unless ( $timespans_id );

    my $timespan = $db->require_by_id( 'timespans', $timespans_id );
    my $cd       = $db->require_by_id( 'snapshots', $timespan->{ snapshots_id } );

    my $topic = $db->require_by_id( 'topics', $cd->{ topics_id } );

    if ( my $qs_id = $timespan->{ foci_id } )
    {
        $timespan->{ focus } = $db->find_by_id( 'foci', $qs_id );
        $cd->{ focus }       = $timespan->{ focus };
        $topic->{ focus }    = $timespan->{ focus };
    }

    # add shortcut field names to make it easier to refer to in tt2
    $timespan->{ timespans_id } = $timespan->{ timespans_id };
    $timespan->{ snap_id }      = $timespan->{ snapshots_id };
    $timespan->{ snapshot }     = $cd;
    $cd->{ snap_id }            = $timespan->{ snapshots_id };

    _add_timespan_model_reliability( $db, $timespan );

    return ( $timespan, $cd, $topic );
}

# get a media_type_stats hash for the given timespan that has the following format:
# { story_count =>
#   [ { media_type => 'Blog', num_stories => $num_stories, percent_stories => $percent_stories },
#     { media_type => 'Tech Media', num_stories => $num_stories, percent_stories => $percent_stories },
#     ...
#   ]
# { link_weight =>
#   [ { media_type => 'Blog', link_weight => $link_weight, percent_link_weight => $percent_link_weight },
#     { media_type => 'General Online News Media', link_weight => $link_weight, percent_link_weight => $percent_link_weight },
#     ...
#   ]
#
# optionally only include stories in the given list of stories_ids.
# must be called within a transaction.
sub _get_media_type_stats_for_timespan
{
    my ( $db, $stories_ids ) = @_;

    my $stories_clause = '1=1';
    if ( $stories_ids )
    {
        $stories_ids = [ map { int( $_ ) } @{ $stories_ids } ];

        my $ids_table = $db->get_temporary_ids_table( $stories_ids );
        $stories_clause = "s.stories_id in ( select id from $ids_table )";
    }

    my $story_count = $db->query( <<END )->hashes;
with media_type_stats as (
    select
            s.media_type,
            count(*) num_stories,
            sum( media_inlink_count ) link_weight
        from
            snapshot_stories_with_types s
            join snapshot_story_link_counts slc on ( s.stories_id = slc.stories_id )
        where
            $stories_clause
        group by s.media_type
),

media_type_sums as (
    select sum( num_stories ) sum_num_stories, sum( link_weight ) sum_link_weight from media_type_stats
)

select
        media_type,
        num_stories,
        case when sum_num_stories = 0
            then
                0
            else
                round( ( num_stories / sum_num_stories ) * 100 )
            end percent_stories,
        link_weight,
        case when sum_link_weight = 0
            then
                0
            else
                round( ( link_weight / sum_link_weight ) * 100 )
            end percent_link_weight
    from
        media_type_stats
        cross join media_type_sums
    order by num_stories desc;
END

    my $link_weight = [ @{ $story_count } ];
    $link_weight = [ sort { $b->{ link_weight } <=> $a->{ link_weight } } @{ $link_weight } ];

    return { story_count => $story_count, link_weight => $link_weight };
}

# view timelices, with links to csv and gexf files
sub view_timespan : Local
{
    my ( $self, $c, $timespans_id ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my $live = $c->req->param( 'l' );

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $timespans_id );

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, $live );

    MediaWords::TM::Snapshot::update_timespan_counts( $db, $timespan, $live ) if ( $live );

    my $top_media = _get_top_media_for_timespan( $db, $timespan );
    my $top_stories = _get_top_stories_for_timespan( $db, $timespan );

    $db->commit;

    $c->stash->{ timespan }    = $timespan;
    $c->stash->{ snapshot }    = $cd;
    $c->stash->{ topic }       = $topic;
    $c->stash->{ top_media }   = $top_media;
    $c->stash->{ top_stories } = $top_stories;
    $c->stash->{ live }        = $live;
    $c->stash->{ template }    = 'tm/view_timespan.tt2';
}

# download a csv field from timespans_id or generate the
# csv for the same data live from the topic data.
sub _download_timespan_csv
{
    my ( $c, $timespans_id, $table, $live ) = @_;

    die( "illegal table name '$table'" )
      unless ( grep { $_ eq $table } qw(stories story_links media medium_links timespan_tweets) );

    my $db = $c->dbis;

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $timespans_id );

    $db->begin;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, $live );

    my $csv  = eval( 'MediaWords::TM::Snapshot::get_' . $table . '_csv( $db, $timespan )' );
    my $file = "${ table }.csv";

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

    $db->commit;

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/csv; charset=UTF-8' );
    $c->response->content_length( bytes::length( $csv ) );
    $c->response->body( $csv );
}

# download a csv file with the facebook and twitter stats for the topic stories
sub snapshot_social : Local
{
    my ( $self, $c, $timespans_id ) = @_;

    my $live = $c->req->param( 'l' );

    my $db = $c->dbis;

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $timespans_id );

    $db->begin;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, $live );

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<SQL );
select
        s.stories_id, s.url, s.title, m.name medium_name, m.media_id, m.url medium_url,
        sst.twitter_url_tweet_count, sst.twitter_api_collect_date,
        ss.facebook_share_count, ss.facebook_comment_count, ss.facebook_api_collect_date
    from snapshot_stories s
        join snapshot_media m on ( s.media_id = m.media_id )
        join story_statistics ss on ( s.stories_id = ss.stories_id )
        left join story_statistics_twitter sst on ( s.stories_id = sst.stories_id )
SQL

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

    $db->commit;

    my $file = "snapshot_social_${ timespans_id }.csv";

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/csv; charset=UTF-8' );
    $c->response->content_length( bytes::length( $csv ) );
    $c->response->body( $csv );
}

# download the stories_csv for the given timespan
sub snapshot_stories : Local
{
    my ( $self, $c, $timespans_id ) = @_;

    _download_timespan_csv( $c, $timespans_id, 'stories', $c->req->params->{ l } );
}

# download the story_links_csv for the given timespan
sub snapshot_story_links : Local
{
    my ( $self, $c, $timespans_id ) = @_;

    _download_timespan_csv( $c, $timespans_id, 'story_links', $c->req->params->{ l } );
}

# download the media_csv for the given timespan
sub snapshot_media : Local
{
    my ( $self, $c, $timespans_id ) = @_;

    _download_timespan_csv( $c, $timespans_id, 'media', $c->req->params->{ l } );
}

# download the medium_links_csv for the given timespan
sub snapshot_medium_links : Local
{
    my ( $self, $c, $timespans_id ) = @_;

    _download_timespan_csv( $c, $timespans_id, 'medium_links', $c->req->params->{ l } );
}

sub snapshot_timespan_tweets : Local
{
    my ( $self, $c, $timespans_id ) = @_;

    _download_timespan_csv( $c, $timespans_id, 'timespan_tweets', 0 );
}

# download the gexf file for the timespan.  if the 'l' param is 1, use live data instead of
# snapshoted data for the timespan.  if using a snapshot, use an existing media.gexf file if it exists.
sub gexf : Local
{
    my ( $self, $c, $timespans_id, $csv ) = @_;

    my $l                    = $c->req->params->{ l };
    my $color_field          = $c->req->params->{ cf };
    my $num_media            = $c->req->params->{ nm };
    my $include_weights      = $c->req->params->{ w };
    my $max_links_per_medium = $c->req->params->{ lpm };

    my $db = $c->dbis;

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $timespans_id );

    my $gexf;

    if ( !$l )
    {
        ( $gexf ) = $db->query( <<END, $timespan->{ timespans_id } )->flat;
select file_content from timespan_files where timespans_id = ? and file_name = 'media.gexf'
END
    }

    if ( !$gexf )
    {
        MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, $l );
        my $gexf_options = {
            color_field          => $color_field,
            max_media            => $num_media,
            include_weights      => $include_weights,
            max_links_per_medium => $max_links_per_medium
        };

        $gexf = MediaWords::TM::Snapshot::get_gexf_snapshot( $db, $timespan, $gexf_options );
    }

    my $base_url = $c->uri_for( '/' );

    $gexf =~ s/\[_mc_base_url_\]/$base_url/g;

    my $file = "media.gexf";

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/gexf; charset=UTF-8' );
    $c->response->content_length( bytes::length( $gexf ) );
    $c->response->body( $gexf );
}

# download a csv field from snapshots
sub _download_snap_csv
{
    my ( $c, $snapshots_id, $csv ) = @_;

    my $file = "${ csv }.csv";

    my $db = $c->dbis;

    my $snap_file = $db->query( <<SQL, $snapshots_id, $file )->hash;
select * from snap_files where snapshots_id = ? and file_name = ?
SQL

    die( "no $file snap_file for snapshot $snapshots_id" ) unless ( $snap_file );

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/csv; charset=UTF-8' );
    $c->response->content_length( bytes::length( $snap_file->{ file_content } ) );
    $c->response->body( $snap_file->{ file_content } );
}

# download the daily_counts_csv for the given snapshot
sub snapshot_daily_counts : Local
{
    my ( $self, $c, $snapshots_id ) = @_;

    _download_snap_csv( $c, $snapshots_id, 'daily_counts' );

    return 1;
}

# download the weekly_counts_csv for the given snapshot
sub snapshot_weekly_counts : Local
{
    my ( $self, $c, $snapshots_id ) = @_;

    _download_snap_csv( $c, $snapshots_id, 'weekly_counts' );

    return 1;
}

# return the latest snapshot if it is not the snapshot to which the timespan belongs.  otherwise return undef.
sub _get_latest_snapshot
{
    my ( $db, $timespan ) = @_;

    my $latest_snapshot = $db->query( <<END, $timespan->{ timespans_id } )->hash;
select latest.* from snapshots latest, snapshots current, timespans timespan
    where timespan.timespans_id = ? and
        current.snapshots_id = timespan.snapshots_id and
        latest.snapshots_id > current.snapshots_id and
        latest.topics_id = current.topics_id
    order by latest.snapshots_id desc
    limit 1
END

    return $latest_snapshot;
}

# fetch the medium from the snapshot_media table
sub _get_medium_from_snapshot_tables
{
    my ( $db, $media_id ) = @_;

    return $db->query( <<SQL, $media_id )->hash;
select *
    from snapshot_media_with_types m
        join snapshot_medium_link_counts mlc on ( m.media_id = mlc.media_id )
    where mlc.media_id = ?
SQL
}

# get the medium with the medium_stories, inlink_stories, and outlink_stories and associated
# counts. assumes the existence of snapshot_* stories as created by
# MediaWords::TM::Snapshot::setup_temporary_snapshot_tables
sub _get_medium_and_stories_from_snapshot_tables
{
    my ( $db, $media_id ) = @_;

    my $medium = _get_medium_from_snapshot_tables( $db, $media_id );

    return unless ( $medium );

    $medium->{ stories } = $db->query(
        <<END,
SELECT s.*,
       m.name AS medium_name,
       m.media_type,
       slc.inlink_count,
       slc.media_inlink_count,
       slc.outlink_count,
       slc.simple_tweet_count,
       slc.normalized_tweet_count,
       slc.bitly_click_count
FROM snapshot_stories AS s,
     snapshot_media_with_types AS m,
     snapshot_story_link_counts AS slc
WHERE s.stories_id = slc.stories_id
  AND s.media_id = m.media_id
  AND s.media_id = ?
ORDER BY slc.media_inlink_count DESC
limit 50
END
        $media_id
    )->hashes;

    MediaWords::DBI::Stories::GuessDate::add_date_is_reliable_to_stories( $db, $medium->{ stories } );
    MediaWords::DBI::Stories::GuessDate::add_undateable_to_stories( $db, $medium->{ stories } );

    $db->query( <<SQL, $medium->{ media_id } );
create temporary table tm_medium_stories_ids as select stories_id from snapshot_stories where media_id = ?
SQL

    $medium->{ inlink_stories } = $db->query(
        <<END
with inlinks as (
    select source_stories_id, ref_stories_id
        from snapshot_story_links
        where ref_stories_id in ( select stories_id from tm_medium_stories_ids )
),

inlink_stories as (
    select * from snapshot_stories s join inlinks l on ( s.stories_id = l.source_stories_id )
)
SELECT DISTINCT s.*,
                sm.name AS medium_name,
                sm.media_type,
                sslc.media_inlink_count,
                sslc.inlink_count,
                sslc.outlink_count,
                sslc.simple_tweet_count,
                sslc.normalized_tweet_count,
                sslc.bitly_click_count
FROM inlink_stories AS s,
     snapshot_story_link_counts AS sslc,
     snapshot_media_with_types AS sm
WHERE s.stories_id = sslc.stories_id
  AND s.media_id = sm.media_id
ORDER BY sslc.media_inlink_count DESC
limit 50
END
    )->hashes;

    MediaWords::DBI::Stories::GuessDate::add_date_is_reliable_to_stories( $db, $medium->{ inlink_stories } );
    MediaWords::DBI::Stories::GuessDate::add_undateable_to_stories( $db, $medium->{ inlink_stories } );

    $medium->{ outlink_stories } = $db->query(
        <<END
with outlinks as (
    select source_stories_id, ref_stories_id
        from snapshot_story_links
        where source_stories_id in ( select stories_id from tm_medium_stories_ids )
),

outlink_stories as (
    select * from snapshot_stories s join outlinks l on ( s.stories_id = l.ref_stories_id )
)

SELECT DISTINCT r.*,
                rm.name AS medium_name,
                rm.media_type,
                rslc.media_inlink_count,
                rslc.inlink_count,
                rslc.outlink_count,
                rslc.simple_tweet_count,
                rslc.normalized_tweet_count,
                rslc.bitly_click_count
FROM outlink_stories AS r,
     snapshot_story_link_counts AS rslc,
     snapshot_media_with_types AS rm
WHERE r.stories_id = rslc.stories_id
  AND r.media_id = rm.media_id
ORDER BY rslc.media_inlink_count DESC
limit 50
END
    )->hashes;

    MediaWords::DBI::Stories::GuessDate::add_date_is_reliable_to_stories( $db, $medium->{ outlink_stories } );
    MediaWords::DBI::Stories::GuessDate::add_undateable_to_stories( $db, $medium->{ outlink_stories } );

    return $medium;
}

# get data about the medium as it existed in the given timespan.  include medium_stories,
# inlink_stories, and outlink_stories from the timespan as well.
sub _get_timespan_medium_and_stories
{
    my ( $db, $timespan, $media_id ) = @_;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan );

    my $medium = _get_medium_and_stories_from_snapshot_tables( $db, $media_id );

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

    return $medium;
}

# get live data about the medium within the given topic.  Include medium_stories,
# inlink_stories, and outlink_stories.
sub _get_live_medium_and_stories
{
    my ( $db, $topic, $timespan, $media_id ) = @_;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, 1 );

    my $medium = _get_medium_and_stories_from_snapshot_tables( $db, $media_id );

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

    return $medium;
}

# return undef if given fields in the given objects are the same and the
# list_field in the given lists are the same.   Otherwise return a string list
# of the fields and lists for which there are differences.
sub _get_object_diffs
{
    my ( $a, $b, $fields, $lists, $list_field ) = @_;

    my $diffs = [];

    for my $field ( @{ $fields } )
    {
        push( @{ $diffs }, $field ) if ( $a->{ $field } ne $b->{ $field } );
    }

    for my $list ( @{ $lists } )
    {
        my $a_ids = [ map { $_->{ $list_field } } @{ $a->{ $list } } ];
        my $b_ids = [ map { $_->{ $list_field } } @{ $b->{ $list } } ];

        my $lc = List::Compare->new( $a_ids, $b_ids );
        if ( !$lc->is_LequivalentR() )
        {
            my $list_name = $list;
            $list_name =~ s/_/ /g;
            push( @{ $diffs }, $list_name );
        }
    }

    return ( @{ $diffs } ) ? join( ", ", @{ $diffs } ) : undef;
}

# check each of the following for differences between the live and snapshot medium:
# * name
# * url
# * ids of stories
# * ids of inlink_stories
# * ids of outlink_stories
#
# return undef if there are no diffs and otherwise a string list of the
# attributes (above) for which there are differences
sub _get_live_medium_diffs
{
    my ( $snapshot_medium, $live_medium ) = @_;

    if ( !$live_medium )
    {
        return 'medium is no longer in topic';
    }

    return _get_object_diffs(
        $snapshot_medium, $live_medium,
        [ qw(name url) ],
        [ qw(stories inlink_stories outlink_stories) ], 'stories_id'
    );
}

# view medium:
# * live if l=1 is specified, otherwise as a snapshot
# * within the context of a timespan if a timespan is specific
#   via timespan=<id>, otherwise within a whole topic if 'c=<id>'
sub medium : Local
{
    my ( $self, $c, $media_id ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $c->req->param( 'timespan' ) );

    my $live = $c->req->param( 'l' );

    my $medium;
    if ( $live )
    {
        $medium = _get_live_medium_and_stories( $db, $topic, $timespan, $media_id );
    }
    else
    {
        $medium = _get_timespan_medium_and_stories( $db, $timespan, $media_id );
    }

    $db->commit;

    $c->stash->{ timespan } = $timespan;
    $c->stash->{ snapshot } = $cd;
    $c->stash->{ topic }    = $topic;
    $c->stash->{ medium }   = $medium;
    $c->stash->{ live }     = $live;
    $c->stash->{ template } = 'tm/medium.tt2';
}

# get the story along with inlink_stories and outlink_stories and the associated
# counts.  assumes the existence of snapshot_* stories as created by
# MediaWords::TM::Snapshot::setup_temporary_snapshot_tables
sub _get_story_and_links_from_snapshot_tables
{
    my ( $db, $stories_id ) = @_;

    my $story = $db->query( <<SQL, $stories_id )->hash;
select * from snapshot_stories s join snapshot_story_link_counts slc using ( stories_id ) where s.stories_id = ?
SQL

    return unless ( $story );

    $story->{ medium } =
      $db->query( "select * from snapshot_media_with_types where media_id = ?", $story->{ media_id } )->hash;

    MediaWords::DBI::Stories::GuessDate::add_date_is_reliable_to_stories( $db, [ $story ] );
    MediaWords::DBI::Stories::GuessDate::add_undateable_to_stories( $db,       [ $story ] );

    $story->{ inlink_stories } = $db->query(
        <<END,
        SELECT DISTINCT s.*,
                        sm.name AS medium_name,
                        sm.media_type,
                        sslc.inlink_count,
                        sslc.media_inlink_count,
                        sslc.outlink_count,
                        sslc.simple_tweet_count,
                        sslc.normalized_tweet_count,
                        sslc.bitly_click_count
        FROM snapshot_stories AS s,
             snapshot_story_link_counts AS sslc,
             snapshot_media_with_types AS sm,
             snapshot_story_links AS sl
        WHERE s.stories_id = sslc.stories_id
          AND s.media_id = sm.media_id
          AND s.stories_id = sl.source_stories_id
          AND sl.ref_stories_id = ?
        ORDER BY sslc.media_inlink_count DESC
        limit 50
END
        $stories_id
    )->hashes;

    MediaWords::DBI::Stories::GuessDate::add_date_is_reliable_to_stories( $db, $story->{ inlink_stories } );
    MediaWords::DBI::Stories::GuessDate::add_undateable_to_stories( $db, $story->{ inlink_stories } );

    $story->{ outlink_stories } = $db->query(
        <<END,
        SELECT DISTINCT r.*,
                        rm.name AS medium_name,
                        rm.media_type,
                        rslc.inlink_count,
                        rslc.media_inlink_count,
                        rslc.outlink_count,
                        rslc.simple_tweet_count,
                        rslc.normalized_tweet_count,
                        rslc.bitly_click_count
        FROM snapshot_stories AS r,
             snapshot_story_link_counts AS rslc,
             snapshot_media_with_types AS rm,
             snapshot_story_links AS sl
        WHERE r.stories_id = rslc.stories_id
          AND r.media_id = rm.media_id
          AND r.stories_id = sl.ref_stories_id
          AND sl.source_stories_id = ?
        ORDER BY rslc.media_inlink_count DESC
        limit 50
END
        $stories_id
    )->hashes;

    MediaWords::DBI::Stories::GuessDate::add_date_is_reliable_to_stories( $db, $story->{ outlink_stories } );
    MediaWords::DBI::Stories::GuessDate::add_undateable_to_stories( $db, $story->{ outlink_stories } );

    return $story;
}

# get data about the story as it existed in the given timespan.  include
# outlinks and inlinks, as well as the date guess method.
sub _get_timespan_story_and_links
{
    my ( $db, $timespan, $stories_id ) = @_;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan );

    my $story = _get_story_and_links_from_snapshot_tables( $db, $stories_id );

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

    return $story;
}

# get data about the story as it exists now in the database, optionally
# in the date range of the if specified
sub _get_live_story_and_links
{
    my ( $db, $topic, $timespan, $stories_id ) = @_;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, 1 );

    my $story = _get_story_and_links_from_snapshot_tables( $db, $stories_id );

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

    return $story;
}

# check each of the following for differences between the live and snapshot story:
# * title
# * url
# * publish_date
# * ids of inlink_stories
# * ids of outlink_stories
# * date_is_reliable
# * undateable
#
# return undef if there are no diffs and otherwise a string list of the
# attributes (above) for which there are differences
sub _get_live_story_diffs
{
    my ( $snapshot_story, $live_story ) = @_;

    if ( !$live_story )
    {
        return 'story is no longer in topic';
    }

    return _get_object_diffs(
        $snapshot_story, $live_story,
        [ qw(title url publish_date date_is_reliable undateable) ],
        [ qw(inlink_stories outlink_stories) ], 'stories_id'
    );
}

# view story as it existed in a snapshot timespan
sub story : Local
{
    my ( $self, $c, $stories_id ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $c->req->param( 'timespan' ) );

    my $live = $c->req->param( 'l' );

    my $story;
    if ( $live )
    {
        $story = _get_live_story_and_links( $db, $topic, $timespan, $stories_id );
    }
    else
    {
        $story = _get_timespan_story_and_links( $db, $timespan, $stories_id );
    }

    $story->{ extracted_text } = MediaWords::DBI::Stories::get_extracted_text( $db, $story );
    $story->{ topic_match } = MediaWords::TM::Mine::story_matches_topic_pattern( $db, $topic, $story );

    $db->commit;

    my $confirm_remove = $c->req->params->{ confirm_remove };

    my $download = $db->query( "select * from downloads where stories_id = ?", $stories_id )->hash;

    $c->stash->{ timespan }       = $timespan;
    $c->stash->{ snapshot }       = $cd;
    $c->stash->{ topic }          = $topic;
    $c->stash->{ story }          = $story;
    $c->stash->{ download }       = $download;
    $c->stash->{ live }           = $live;
    $c->stash->{ confirm_remove } = $confirm_remove;
    $c->stash->{ template }       = 'tm/story.tt2';
}

# list topic_tweets associated with the story
sub story_tweets : Local
{
    my ( $self, $c, $stories_id ) = @_;

    my $db = $c->dbis;

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $c->req->param( 'timespan' ) );

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan );

    my $story = $db->query( <<SQL, $stories_id )->hash;
select * from snapshot_stories s join snapshot_story_link_counts slc using ( stories_id ) where s.stories_id = ?
SQL

    my $tweets = $db->query( <<SQL, $stories_id )->hashes;
select tt.*, tt.data->>'url' url
    from topic_tweets tt
    where
        topic_tweets_id in (
            select topic_tweets_id
                from snapshot_timespan_tweets stt
                    join topic_tweet_full_urls ttfu using ( topic_tweets_id )
                where
                    ttfu.stories_id = \$1
        )
    order by tt.publish_date
SQL

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

    $c->stash->{ timespan } = $timespan;
    $c->stash->{ snapshot } = $cd;
    $c->stash->{ topic }    = $topic;
    $c->stash->{ story }    = $story;
    $c->stash->{ tweets }   = $tweets;
    $c->stash->{ template } = 'tm/story_tweets.tt2';
}

# get the text for a sql query that returns all of the story ids that
# match the given search query within solr.
sub _get_stories_id_search_query
{
    my ( $db, $q ) = @_;

    return 'select stories_id from snapshot_story_link_counts' unless ( $q );

    $q =~ s/^\s+//;
    $q =~ s/\s+$//;

    my $period_stories_ids = $db->query( "select stories_id from snapshot_story_link_counts" )->flat;

    my $stories_clause = "stories_id:(" . join( ' ', @{ $period_stories_ids } ) . ")";

    my $stories_ids = MediaWords::Solr::search_for_stories_ids( $db, { q => $q, fq => $stories_clause } );

    return @{ $stories_ids } ? join( ',', @{ $stories_ids } ) : -1;
}

# get solr params for running a query against solr in the given timespan
sub _get_solr_params_for_timespan_query
{
    my ( $timespan, $q ) = @_;

    my $params = { fq => "timespans_id:$timespan->{ timespans_id }" };

    $params->{ q }    = ( defined( $q ) && $q ne '' ) ? $q : '*:*';
    $params->{ rows } = 100_000;
    $params->{ sort } = 'random_1 asc';

    return $params;
}

# get the top words used by the given set of stories, sorted by tfidf against all words
# in the topic
sub _get_story_words ($$$$$;$)
{
    my ( $db, $topic, $timespan, $q, $sort_by_count, $num_words ) = @_;

    my $solr_p = _get_solr_params_for_timespan_query( $timespan, $q );
    my $stories_ids = MediaWords::Solr::search_for_stories_ids( $db, $solr_p );

    if ( !$num_words )
    {
        $num_words = int( log( scalar( @{ $stories_ids } ) + 1 ) * 10 );
        $num_words = ( $num_words < 100 ) ? $num_words : 100;
    }

    my $story_words = MediaWords::Solr::WordCounts->new( db => $db, %{ $solr_p } )->get_words;

    splice( @{ $story_words }, $num_words );

    if ( !$sort_by_count )
    {
        for my $story_word ( @{ $story_words } )
        {
            my $solr_df_query = "{~ topic:$topic->{ topics_id } }";

            my $df = MediaWords::Solr::get_num_found(
                $db,
                {
                    q  => "+sentence:" . $story_word->{ term },
                    fq => $solr_df_query
                }
            );

            if ( $df )
            {
                $story_word->{ tfidf }       = $story_word->{ count } / sqrt( $df );
                $story_word->{ total_count } = $df;
            }
            else
            {
                $story_word->{ tfidf } = 0;
            }
        }
        $story_words = [ sort { $b->{ tfidf } <=> $a->{ tfidf } } @{ $story_words } ];
    }

    map { $story_words->[ $_ ]->{ rank } = $_ + 1 } ( 0 .. $#{ $story_words } );

    return $story_words;
}

# remove all stories in the stories_ids cgi param from the topic
sub remove_stories : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $timespans_id = $c->req->params->{ timespan };
    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $timespans_id );

    my $live        = $c->req->params->{ l };
    my $stories_ids = $c->req->params->{ stories_ids };
    my $topics_id   = $topic->{ topics_id };

    $stories_ids = [ $stories_ids ] if ( $stories_ids && !ref( $stories_ids ) );

    for my $stories_id ( @{ $stories_ids } )
    {
        _remove_story_from_topic( $db, $stories_id, $topics_id, $c->user->username, $c->req->params->{ reason } );
    }

    my $status_msg = scalar( @{ $stories_ids } ) . " stories removed from topic.";
    $c->res->redirect( $c->uri_for( "/admin/tm/view_timespan/$timespans_id", { l => $live, status_msg => $status_msg } ) );
}

# display a word cloud of the words in the stories given in the stories_ids cgi param
# optionaly tfidf all stories in the given topic
sub word_cloud : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my $timespans_id = $c->req->params->{ timespan };
    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $timespans_id );

    my $live          = $c->req->params->{ l };
    my $q             = $c->req->params->{ q };
    my $sort_by_count = $c->req->params->{ sort_by_count };

    my $words = _get_story_words( $db, $topic, $timespan, $q, $sort_by_count );

    $c->stash->{ timespan }      = $timespan;
    $c->stash->{ snapshot }      = $cd;
    $c->stash->{ topic }         = $topic;
    $c->stash->{ live }          = $live;
    $c->stash->{ words }         = $words;
    $c->stash->{ q }             = $q;
    $c->stash->{ sort_by_count } = $sort_by_count;
    $c->stash->{ template }      = 'tm/words.tt2';
}

# do a basic story search based on the story sentences, title, url, media name, and media url
sub search_stories : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my $timespans_id = $c->req->params->{ timespan } + 0;
    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $timespans_id );

    my $live = $c->req->params->{ l };
    my $reason = $c->req->params->{ reason } || '';

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, $live );

    my $query = $c->req->params->{ q };
    my $search_query = _get_stories_id_search_query( $db, $query );

    my $order = $c->req->params->{ order } || '';
    my $order_clause =
      $order eq 'bitly_click_count' ? 'slc.bitly_click_count desc nulls last' : 'slc.media_inlink_count desc';

    my $stories = $db->query(
        <<"END"
        SELECT s.*,
               m.name AS medium_name,
               m.media_type,
               slc.inlink_count,
               slc.media_inlink_count,
               slc.outlink_count,
               slc.simple_tweet_count,
               slc.normalized_tweet_count,
               slc.bitly_click_count
        FROM snapshot_stories AS s,
             snapshot_media_with_types AS m,
             snapshot_story_link_counts AS slc
        WHERE s.stories_id = slc.stories_id
          AND s.media_id = m.media_id
          AND s.stories_id IN ( $search_query )
        ORDER BY $order_clause
        limit 1000
END
    )->hashes;

    MediaWords::DBI::Stories::GuessDate::add_date_is_reliable_to_stories( $db, $stories );
    MediaWords::DBI::Stories::GuessDate::add_undateable_to_stories( $db, $stories );

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

    $db->commit;

    my $topics_id = $topic->{ topics_id };

    if ( $c->req->params->{ missing_solr_stories } )
    {
        my $solr_query       = "{! topic:$topic->{ topics_id } }";
        my $solr_stories_ids = MediaWords::Solr::search_for_stories_ids( $db, { q => $solr_query } );
        my $solr_lookup      = {};
        map { $solr_lookup->{ $_ } = 1 } @{ $solr_stories_ids };
        $stories = [ grep { !$solr_lookup->{ $_->{ stories_id } } } @{ $stories } ];
    }

    if ( $c->req->params->{ remove_stories } )
    {
        $db->begin;

        eval {
            map { _remove_story_from_topic( $db, $_->{ stories_id }, $topics_id, $c->user->username, $reason ) }
              @{ $stories };
        };
        if ( $@ )
        {
            $db->rollback;

            my $error = "Unable to remove stories: $@";
            $c->res->redirect(
                $c->uri_for( "/admin/tm/view_timespan/$timespans_id", { l => $live, status_msg => $error } ) );
            return;
        }

        $db->commit;

        my $status_msg = "stories removed from topic.";
        $c->res->redirect(
            $c->uri_for( "/admin/tm/view_timespan/$timespans_id", { l => $live, status_msg => $status_msg } ) );
        return;
    }

    $c->stash->{ timespan } = $timespan;
    $c->stash->{ snapshot } = $cd;
    $c->stash->{ topic }    = $topic;
    $c->stash->{ stories }  = $stories;
    $c->stash->{ query }    = $query;
    $c->stash->{ live }     = $live;
    $c->stash->{ template } = 'tm/stories.tt2';
}

# do a basic media search based on the story sentences, title, url, media name, and media url
sub search_media : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $c->req->param( 'timespan' ) );

    my $live = $c->req->param( 'l' );

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, $live );

    my $query = $c->req->param( 'q' );
    my $search_query;

    if ( $query )
    {
        my $stories_id_query = _get_stories_id_search_query( $db, $query );
        $search_query =
          "AND m.media_id IN ( select media_id from snapshot_stories where stories_id in ( $stories_id_query ) )";
    }
    else
    {
        $search_query = '';
    }

    my $order = $c->req->params->{ order } || '';
    my $order_clause = $order eq 'bitly_click_count' ? 'mlc.bitly_click_count desc' : 'mlc.media_inlink_count desc';

    my $media = $db->query(
        <<"END"
        SELECT DISTINCT m.*,
                        mlc.inlink_count,
                        mlc.media_inlink_count,
                        mlc.outlink_count,
                        mlc.bitly_click_count,
                        mlc.simple_tweet_count,
                        mlc.normalized_tweet_count,
                        mlc.story_count
        FROM snapshot_media_with_types AS m,
             snapshot_medium_link_counts AS mlc
        WHERE m.media_id = mlc.media_id
          $search_query
        ORDER BY $order_clause
        limit 1000
END
    )->hashes;

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

    $db->commit;

    $c->stash->{ timespan } = $timespan;
    $c->stash->{ snapshot } = $cd;
    $c->stash->{ topic }    = $topic;
    $c->stash->{ media }    = $media;
    $c->stash->{ query }    = $query;
    $c->stash->{ live }     = $live;
    $c->stash->{ template } = 'tm/media.tt2';
}

# remove the given story from the given topic; die()s on error
sub _remove_story_from_topic($$$$$)
{
    my ( $db, $stories_id, $topics_id, $user, $reason ) = @_;

    $reason ||= '';

    eval {

        # Do the change
        MediaWords::TM::Mine::remove_story_from_topic( $db, $stories_id, $topics_id );

        # Log the activity
        my $change = { 'stories_id' => $stories_id + 0 };
        unless (
            MediaWords::DBI::Activities::log_activity(
                $db, 'tm_remove_story_from_topic', $user, $topics_id, $reason, $change
            )
          )
        {
            die "Unable to log the story removal activity.";
        }

    };
    if ( $@ )
    {
        die "Unable to remove story $stories_id from topic $topics_id: $@";
    }
}

# merge source_media_id into target_media_id
sub merge_media : Local : FormConfig
{
    my ( $self, $c, $media_id ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $c->req->param( 'timespan' ) );

    my $live = 1;

    $c->stash->{ topic }    = $topic;
    $c->stash->{ snap }     = $cd;
    $c->stash->{ timespan } = $timespan;
    $c->stash->{ live }     = $live;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, $live );

    my $medium = _get_medium_from_snapshot_tables( $db, $media_id );

    my $to_media_id = $c->req->param( 'to_media_id' ) // 0;
    $to_media_id = $to_media_id + 0;
    my $to_medium = _get_medium_from_snapshot_tables( $db, $to_media_id ) if ( $to_media_id );

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

    $db->commit;

    my $timespans_id = $timespan->{ timespans_id } + 0;

    if ( !$medium )
    {
        my $error = 'This medium no longer exists in the live data';
        my $u = $c->uri_for( "/admin/tm/view/$topic->{ topics_id }", { error_msg => $error } );
        $c->response->redirect( $u );
        return;
    }

    my $form = $c->stash->{ form };

    if ( !$form->submitted_and_valid )
    {
        $c->stash->{ medium }   = $medium;
        $c->stash->{ template } = 'tm/merge_media.tt2';
        return;
    }

    if ( !$to_medium )
    {
        my $error = 'The destination medium no longer exists in the live data';
        my $u = $c->uri_for( "/admin/tm/medium/$media_id", { timespan => $timespans_id, error_msg => $error } );
        $c->response->redirect( $u );
        return;
    }

    # Start transaction
    $db->begin;

    my $reason = $c->req->param( 'reason' ) || '';

    # Make the merge
    eval { MediaWords::TM::Mine::merge_dup_medium_all_topics( $db, $medium, $to_medium ); };
    if ( $@ )
    {
        $db->rollback;

        my $error = "Unable to merge media: $@";
        my $u = $c->uri_for( "/admin/tm/medium/$media_id", { timespan => $timespans_id, error_msg => $error } );
        $c->response->redirect( $u );
        return;
    }

    # Log the activity
    my $change = {
        'media_id'     => $media_id + 0,
        'to_media_id'  => $to_media_id + 0,
        'timespans_id' => $timespans_id + 0
    };
    unless (
        MediaWords::DBI::Activities::log_activity(
            $db, 'tm_media_merge', $c->user->username, $topic->{ topics_id } + 0,
            $reason, $change
        )
      )
    {
        $db->rollback;

        my $error = "Unable to log the activity of merging media.";
        my $u = $c->uri_for( "/admin/tm/medium/$media_id", { timespan => $timespans_id, error_msg => $error } );
        $c->response->redirect( $u );
        return;
    }

    # Things went fine
    $db->commit;

    my $status_msg = 'The media have been merged in all topics.';
    my $u = $c->uri_for( "/admin/tm/medium/$to_media_id", { timespan => $timespans_id, status_msg => $status_msg, l => 1 } );
    $c->response->redirect( $u );
    return;
}

# merge $story into $to_story in $topic
sub _merge_stories
{
    my ( $c, $topic, $story, $to_story, $reason ) = @_;

    $reason ||= '';

    my $db = $c->dbis;

    return 1 if ( $story->{ stories_id } == $to_story->{ stories_id } );

    eval { MediaWords::TM::Mine::merge_dup_story( $db, $topic, $story, $to_story ); };
    if ( $@ )
    {
        $db->rollback;

        ERROR "Unable to merge stories: $@";
        return 0;
    }

    # Log the activity
    my $change = { stories_id => $story->{ stories_id }, to_stories_id => $to_story->{ stories_id } };

    my $logged = MediaWords::DBI::Activities::log_activity( $db, 'tm_story_merge', $c->user->username, $topic->{ topics_id },
        $reason, $change );

    if ( !$logged )
    {
        $db->rollback;

        ERROR "Unable to log the activity of merging stories.";
        return 0;
    }

    return 1;
}

# merge stories_id into to_stories_id
sub merge_stories : Local : FormConfig
{
    my ( $self, $c, $stories_id ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $c->req->param( 'timespan' ) );

    my $live = 1;

    $c->stash->{ topic }    = $topic;
    $c->stash->{ snap }     = $cd;
    $c->stash->{ timespan } = $timespan;
    $c->stash->{ live }     = $live;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, $live );

    my $story = $db->query( "select * from snapshot_stories where stories_id = ?", $stories_id )->hash;

    my $to_stories_id = $c->req->param( 'to_stories_id' ) + 0;
    my $to_story = $db->query( "select * from snapshot_stories where stories_id = ?", $to_stories_id )->hash
      if ( $to_stories_id );

    MediaWords::TM::Snapshot::discard_temp_tables( $db );

    $db->commit;

    my $timespans_id = $timespan->{ timespans_id } + 0;

    if ( !$story )
    {
        my $error = 'The requested story no longer exists in the live data';
        my $u = $c->uri_for( "/admin/tm/view/$topic->{ topics_id }", { error_msg => $error } );
        $c->response->redirect( $u );
        return;
    }

    my $form = $c->stash->{ form };

    if ( !$form->submitted_and_valid )
    {
        $c->stash->{ story }    = $story;
        $c->stash->{ template } = 'tm/merge_stories.tt2';
        return;
    }

    # Start transaction
    $db->begin;

    my $reason = $c->req->param( 'reason' ) || '';

    # Make the merge
    my $stories_merged = _merge_stories( $c, $topic, $story, $to_story, $reason );

    $db->commit;

    my $status_msg;
    if ( !$stories_merged )
    {
        $status_msg = 'There was an error merging the stories.';
    }
    else
    {
        $status_msg = 'The stories have been merged in this topic.';
    }

    my $u =
      $c->uri_for( "/admin/tm/story/$to_stories_id", { timespan => $timespans_id, status_msg => $status_msg, l => 1 } );
    $c->response->redirect( $u );
}

# parse story ids and associated urls from param names, along
# with the associated assume_match and manual_redirect options for
# each url.  call MediaWords::Util::URL::unredirect_story on
# each story and its urls and associated options.
sub unredirect_param_stories
{
    my ( $c ) = @_;

    my $db = $c->dbis;

    my $story_urls = {};
    for my $name ( keys( %{ $c->req->params } ) )
    {
        next unless ( $name =~ /^include_url_(\d+)_(\d+)_(.*)$/ );
        my ( $stories_id, $topics_id, $url ) = ( $1, $2, $3 );

        my $param_tag = "${ stories_id }_${ topics_id }_${ url }";

        my $url_options = {
            url             => $url,
            assume_match    => normalize_boolean_for_db( $c->req->params->{ "assume_match_${ param_tag }" } ),
            manual_redirect => $c->req->params->{ "manual_redirect_${ param_tag }" }
        };

        push( @{ $story_urls->{ $stories_id }->{ $topics_id } }, $url_options );
    }

    while ( my ( $stories_id, $topic_urls ) = each( %{ $story_urls } ) )
    {
        while ( my ( $topics_id, $urls ) = each( %{ $topic_urls } ) )
        {
            my $story = $db->find_by_id( 'stories', $stories_id )
              || die( "Unable to find story '$stories_id'" );

            my $topic = $db->find_by_id( 'topics', $topics_id )
              || die( "Unable to find topic '$topics_id'" );

            MediaWords::TM::Mine::unredirect_story( $db, $topic, $story, $urls );
        }
    }
}

# action to confirm splitting up media source based on its stories' original, unredirected urls
sub unredirect_medium : Local
{
    my ( $self, $c, $media_id ) = @_;

    my $db = $c->dbis;

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $c->req->param( 'timespan' ) );
    my $live = 1;

    my $medium = $db->find_by_id( 'media', $media_id ) || die( "Unable to find medium '$media_id'" );

    if ( $c->req->params->{ submit } )
    {
        MediaWords::TM::Mine::add_medium_url_to_ignore_redirects( $db, $medium );
        unredirect_param_stories( $c );

        my $msg = "The medium has been reprocessed to use the original urls of its stories.";
        $c->res->redirect( $c->uri_for( "/admin/tm/view/$topic->{ topics_id }", { status_msg => $msg } ) );
        return;
    }

    my $stories = $db->query( "select * from stories where media_id = ?", $media_id )->hashes;

    map { $_->{ original_urls } = MediaWords::TM::Mine::get_story_original_urls( $db, $_ ) } @{ $stories };

    $c->stash->{ topic }    = $topic;
    $c->stash->{ snap }     = $cd;
    $c->stash->{ timespan } = $timespan;
    $c->stash->{ live }     = $live;
    $c->stash->{ stories }  = $stories;
    $c->stash->{ medium }   = $medium;
    $c->stash->{ template } = 'tm/unredirect_medium.tt2';
}

# List all activities
sub activities : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $p = $c->request->param( 'p' ) || 1;

    my $topic = $c->dbis->query(
        <<END,
        SELECT *
        FROM topics
        WHERE topics_id = ?
END
        $topics_id
    )->hash;

    # Activities which directly or indirectly reference "topics.topics_id" = $topics_id
    my $sql_activities =
      MediaWords::DBI::Activities::sql_activities_which_reference_column( 'topics.topics_id', $topics_id );

    my $qph        = $c->dbis->query_paged_hashes( $sql_activities, $p, $ROWS_PER_PAGE );
    my $activities = $qph->list();
    my $pager      = $qph->pager();

    # FIXME put activity preparation (JSON decoding, description fetching) into
    # a subroutine in order to not repeat oneself.
    for ( my $x = 0 ; $x < scalar @{ $activities } ; ++$x )
    {
        my $activity = $activities->[ $x ];

        # Get activity description
        $activity->{ activity } = MediaWords::DBI::Activities::activity( $activity->{ name } );

        # Decode activity descriptions from JSON
        $activity->{ description } =
          MediaWords::DBI::Activities::decode_activity_description( $activity->{ name }, $activity->{ description_json } );

        $activities->[ $x ] = $activity;
    }

    $c->stash->{ topic }      = $topic;
    $c->stash->{ activities } = $activities;
    $c->stash->{ pager }      = $pager;
    $c->stash->{ pager_url }  = $c->uri_for( '/admin/tm/activities/' . $topics_id ) . '?';

    $c->stash->{ template } = 'tm/activities.tt2';
}

# delete list of story ids from topic
sub delete_stories : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $db = $c->dbis;

    my $topic = $db->find_by_id( 'topics', $topics_id )
      || die( "unable to find topic '$topics_id'" );

    my $stories_ids_list = $c->req->params->{ stories_ids } || '';
    my $stories_ids = [ grep { /^\d+$/ } split( /\s+/, $stories_ids_list ) ];

    if ( !@{ $stories_ids } )
    {
        $c->stash->{ error_msg } = 'no valid story ids in list' if ( $stories_ids_list );
        $c->stash->{ topic }     = $topic;
        $c->stash->{ template }  = 'tm/delete_stories.tt2';
        return;
    }

    for my $stories_id ( @{ $stories_ids } )
    {
        _remove_story_from_topic( $db, $stories_id, $topics_id, $c->user->username, 'batch removal' );
    }

    my $status_msg = scalar( @{ $stories_ids } ) . " stories removed from topic.";
    $c->res->redirect( $c->uri_for( "/admin/tm/view/$topics_id", { status_msg => $status_msg } ) );
}

# merge list of stories, in keep_id,delete_id format
sub merge_stories_list : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $db = $c->dbis;

    my $topic = $db->find_by_id( 'topics', $topics_id )
      || die( "unable to find topic '$topics_id'" );

    my $stories_ids_list = $c->req->params->{ stories_ids } || '';

    if ( !$stories_ids_list )
    {
        $c->stash->{ topic }    = $topic;
        $c->stash->{ template } = 'tm/merge_stories_list.tt2';
        return;
    }

    my $stories_ids_pairs = MediaWords::Util::CSV::get_csv_string_as_matrix( $stories_ids_list );

    $db->begin;

    my $stories_merged = 1;
    for my $stories_id_pair ( @{ $stories_ids_pairs } )
    {
        my ( $keep_stories_id, $delete_stories_id ) = @{ $stories_id_pair };

        my $keep_story   = $db->find_by_id( 'stories', $keep_stories_id );
        my $delete_story = $db->find_by_id( 'stories', $delete_stories_id );

        $stories_merged = _merge_stories( $c, $topic, $delete_story, $keep_story );
        last unless ( $stories_merged );
    }

    $db->commit if ( $stories_merged );

    my $status_msg;
    if ( $stories_merged )
    {
        $status_msg = 'The stories have been merged in this topic.';
    }
    else
    {
        $status_msg = 'There was an error merging the stories.';
    }

    my $u = $c->uri_for( "/admin/tm/view/$topics_id", { status_msg => $status_msg } );
    $c->response->redirect( $u );
}

# get metrics for links between partisan communities in the form of:
# [
#  [
#   {
#     'source_tag' => 'partisan_2012_liberal',
#     'log_inlink_count' => '29.1699250014423',
#     'ref_tag' => 'partisan_2012_liberal',
#     'source_tags_id' => 29,
#     'inlink_count' => '32',
#     'media_link_count' => '26',
#     'ref_tags_id' => 29
#   },
#   {
#     'source_tag' => 'partisan_2012_liberal',
#     'log_inlink_count' => '38.1536311941017',
#     'ref_tag' => 'partisan_2012_libertarian',
#     'source_tags_id' => 29,
#     'inlink_count' => '61',
#     'media_link_count' => '25',
#     'ref_tags_id' => 30
#   },
#   ...
#  ], [ ... ], ... ]
sub _get_partisan_link_metrics
{
    my ( $db, $stories_ids ) = @_;

    my $stories_clause = '1=1';
    if ( $stories_ids )
    {
        $stories_ids = [ map { int( $_ ) } @{ $stories_ids } ];

        my $ids_table = $db->get_temporary_ids_table( $stories_ids );
        $stories_clause = "s.stories_id in ( select id from $ids_table )";
    }

    my $query = <<END;
-- partisan collection tags
with partisan_tags as (
    select t.*
        from
            tags t
            join tag_sets ts on (t.tag_sets_id = ts.tag_sets_id )
        where
            ts.name = 'collection' and
            t.tag in ( 'partisan_2012_liberal', 'partisan_2012_conservative', 'partisan_2012_libertarian' )
),

-- all stories in the topic belonging to the media tagged with one of the partisan collection tags
partisan_stories as (
    select s.*, t.*
        from
            snapshot_stories s
            join snapshot_media_tags_map mtm on ( s.media_id = mtm.media_id )
            join snapshot_tags t on ( mtm.tags_id = t.tags_id )
            join partisan_tags pt on ( t.tags_id = pt.tags_id )
            join snapshot_tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
        where
            $stories_clause
),

-- full matrix of all partisan tags joined to one another
partisan_tags_matrix as (
    select
            at.tags_id tags_id_a,
            at.tag tag_a,
            at.label label_a,
            bt.tags_id tags_id_b,
            bt.tag tag_b,
            bt.label label_b
        from
            partisan_tags at
            cross join partisan_tags bt
),

-- matrix of all partisan tags that have links to one another
sparse_matrix as (
    select distinct
            ss.tags_id source_tags_id,
            rs.tags_id ref_tags_id,
            count(*) over w media_link_count,
            sum( log( count(*) + 1 ) / log ( 2 ) ) over w log_inlink_count,
            sum( count(*) ) over w inlink_count
        from
            partisan_stories ss
            join snapshot_story_links sl on ( ss.stories_id = sl.source_stories_id )
            join partisan_stories rs on ( rs.stories_id = sl.ref_stories_id )
        group by ss.media_id, ss.tags_id, rs.media_id, rs.tags_id
        window w as ( partition by ss.tags_id, rs.tags_id )
        order by ss.tags_id, rs.tags_id
)

-- join the full matrix to the sparse matrix to add 0 values for partisan tag <-> partisan tag
-- combination that have no links between them (which are not present in the sparse matrix )
select
        ptm.tags_id_a source_tags_id,
        ptm.tag_a as source_tag,
        ptm.label_a as source_label,
        ptm.tags_id_b ref_tags_id,
        ptm.tag_b ref_tag,
        ptm.label_b as ref_label,
        coalesce( sm.media_link_count, 0 ) media_link_count,
        coalesce( sm.log_inlink_count, 0 ) log_inlink_count,
        coalesce( sm.inlink_count, 0 ) inlink_count
    from
        partisan_tags_matrix ptm
        left join sparse_matrix sm on
            ( ptm.tags_id_a = sm.source_tags_id and ptm.tags_id_b = sm.ref_tags_id )

END

    my $link_metrics = $db->query( $query )->hashes;

    # arrange results into a list of lists, sorted by source tags id
    my $last_source_tags_id = 0;
    my $metrics_table       = [];
    for my $m ( @{ $link_metrics } )
    {
        if ( $last_source_tags_id != $m->{ source_tags_id } )
        {
            push( @{ $metrics_table->[ @{ $metrics_table } ] }, $m );
            $last_source_tags_id = $m->{ source_tags_id };
        }
        else
        {
            push( @{ $metrics_table->[ @{ $metrics_table } - 1 ] }, $m );
        }
    }

    return $metrics_table;
}

# generate report on partisan behavior within set
sub partisan : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $timespans_id = $c->req->params->{ timespan };
    my $live         = $c->req->params->{ l };

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $timespans_id );

    $db->begin;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, undef );

    my $metrics_table = _get_partisan_link_metrics( $db );

    $db->commit;

    $c->stash->{ metrics_table } = $metrics_table;
    $c->stash->{ topic }         = $topic;
    $c->stash->{ snap }          = $cd;
    $c->stash->{ timespan }      = $timespan;
    $c->stash->{ live }          = $live;
    $c->stash->{ template }      = 'tm/partisan.tt2';
}

# given a list of word lists as returned by _get_story_words, add a { key_word => 1 } field
# to each word hash for which the rank of that word is higher than the rank for that
# word in any other list
sub _highlight_key_words
{
    my ( $word_lists ) = @_;

    my $word_rank_lookup = {};
    for my $word_list ( @{ $word_lists } )
    {
        for my $word ( @{ $word_list } )
        {
            my $stem = $word->{ stem };
            my $rank = $word->{ rank };
            if ( !$word_rank_lookup->{ $stem } )
            {
                $word_rank_lookup->{ $stem } = { rank => $rank, key_word => $word };
                $word->{ key_word } = 1;
            }
            elsif ( $word_rank_lookup->{ $stem }->{ rank } > $rank )
            {
                $word_rank_lookup->{ $stem }->{ key_word }->{ key_word } = 0;
                $word_rank_lookup->{ $stem } = { rank => $rank, key_word => $word };
                $word->{ key_word } = 1;
            }
            elsif ( $word_rank_lookup->{ $stem }->{ rank } == $rank )
            {
                $word_rank_lookup->{ $stem }->{ key_word }->{ key_word } = 0;
            }
        }
    }

}

# get the overall timespan for the topic snapshot associated with this timespan
sub _get_overall_timespan
{
    my ( $db, $timespan, $cd ) = @_;

    return $timespan if ( $timespan->{ period } eq 'overall' );

    my $overall_timespan = $db->query( <<END, $timespan->{ snapshots_id } )->hash;
select timespan.* from timespans timespan where snapshots_id = ? and period = 'overall'
END

    die( "Unable to find overall timespan" ) unless ( $overall_timespan );

    return $overall_timespan;
}

# display the 20 most popular words for the 10 most influential media in the given timespan
# or for the 10 most influential media overall
sub influential_media_words : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $timespans_id = $c->req->params->{ timespan };

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $timespans_id );

    my $live    = $c->req->params->{ l };
    my $q       = $c->req->params->{ q };
    my $overall = $c->req->params->{ overall };

    my $media_timespan = $overall ? _get_overall_timespan( $db, $timespan, $cd ) : $timespan;

    $db->begin;
    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $media_timespan, $topic, $live );
    my $top_media = _get_top_media_for_timespan( $db, $media_timespan );
    $db->commit;

    my $num_media = 10;
    my $num_words = 20;

    my $display_media = [];
    my $hide_media    = [];
    for my $medium ( @{ $top_media } )
    {
        my $q = "media_id:$medium->{ media_id }";
        $medium->{ words } = _get_story_words( $db, $topic, $timespan, $q, 1, 20 );
        splice( @{ $medium->{ words } }, $num_words );

        if ( @{ $medium->{ words } } >= ( $num_words / 2 ) )
        {
            push( @{ $display_media }, $medium );
        }
        else
        {
            push( @{ $hide_media }, $medium );
        }

        last if ( @{ $display_media } >= $num_media );
    }

    $top_media = $display_media;

    my $top_words = _get_story_words( $db, $topic, $timespan, undef, 1 );

    _highlight_key_words( [ $top_words, map { $_->{ words } } @{ $top_media } ] );

    $c->stash->{ timespan }   = $timespan;
    $c->stash->{ snap }       = $cd;
    $c->stash->{ topic }      = $topic;
    $c->stash->{ live }       = $live;
    $c->stash->{ top_media }  = $top_media;
    $c->stash->{ hide_media } = $hide_media;
    $c->stash->{ q }          = $q;
    $c->stash->{ top_words }  = $top_words;
    $c->stash->{ overall }    = $overall;
    $c->stash->{ template }   = 'tm/influential_media_words.tt2';
}

# update the media type of the given topic.  if the submitted tag is a 'media_type'
# tag, delete any existing media_type_tag_sets_id tag first.
sub _update_media_type
{
    my ( $db, $medium, $tags_id, $topic ) = @_;

    my $tag = $db->query( <<END, $tags_id )->hash;
select * from tags_with_sets where tags_id = ?
END

    if ( $tag->{ tag_set_name } eq 'media_type' )
    {
        $db->query( <<END, $medium->{ media_id }, $topic->{ media_type_tag_sets_id } );
delete from media_tags_map mtm
    using
        tags t
    where
        mtm.tags_id = t.tags_id and
        t.tag_sets_id = \$2 and
        mtm.media_id = \$1
END
    }

    MediaWords::DBI::Media::update_media_type( $db, $medium, $tags_id );
}

# process form values to add media types according to form parameters.
# each relevant form param has a name of 'media_type_<media_id>'
# (eg. 'media_type_123') and the tags_id of the media_type tag to add.
sub _process_add_media_type_params
{
    my ( $c, $topic ) = @_;

    my $db = $c->dbis;

    for my $type_param ( keys( %{ $c->req->params } ) )
    {
        next unless ( $type_param =~ /media_type_(\d+)/ );

        my $media_id = $1;
        my $tags_id  = $c->req->params->{ $type_param };

        my $medium = $db->query( "select * from media_with_media_types where media_id = ?", $media_id )->hash
          || die( "Unable to find medium '$media_id'" );

        _update_media_type( $db, $medium, $tags_id, $topic );
    }
}

sub _get_media_for_typing : Local
{
    my ( $c, $timespan, $topic ) = @_;

    my $db = $c->dbis;

    my $retype_media_type = $c->req->params->{ retype_media_type } || 'Not Typed';
    my $last_media_id     = $c->req->params->{ last_media_id }     || 0;

    $db->begin;
    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, 1 );

    my $media = $db->query( <<END, $retype_media_type )->hashes;
with ranked_media as (
    select m.*,
            mlc.media_inlink_count,
            mlc.inlink_count,
            mlc.outlink_count,
            mlc.story_count,
            rank() over ( order by mlc.media_inlink_count desc, m.media_id desc ) r
        from
            snapshot_media_with_types m,
            snapshot_medium_link_counts mlc
        where
            m.media_id = mlc.media_id
        order by r
)

select *
    from
        ranked_media m
    where
        m.media_type = ? and
        ( ( $last_media_id = 0 ) or
          ( r > ( select r from ranked_media where media_id = $last_media_id limit 1 ) ) )
    limit 10
END

    $db->commit;

    return $media;
}

# page for adding media types to 'not type'd media
sub add_media_types : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $c->req->params->{ timespan } );
    my $retype_media_type = $c->req->params->{ retype_media_type };

    _process_add_media_type_params( $c, $topic );

    my $media = _get_media_for_typing( $c, $timespan, $topic );
    my $last_media_id = @{ $media } ? $media->[ $#{ $media } ]->{ media_id } : 0;

    my $media_types = MediaWords::DBI::Media::get_media_type_tags( $db, $topic->{ topics_id } );

    $c->stash->{ topic }             = $topic;
    $c->stash->{ snap }              = $cd;
    $c->stash->{ timespan }          = $timespan;
    $c->stash->{ live }              = 1;
    $c->stash->{ media }             = $media;
    $c->stash->{ last_media_id }     = $last_media_id;
    $c->stash->{ media_types }       = $media_types;
    $c->stash->{ retype_media_type } = $retype_media_type;
    $c->stash->{ template }          = 'tm/add_media_types.tt2';
}

# delet a single topic_dates row
sub delete_date : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', $topics_id );

    my $start_date = $c->req->params->{ start_date };
    my $end_date   = $c->req->params->{ end_date };

    die( "missing start_date or end_date" ) unless ( $start_date && $end_date );

    $db->query( <<END, $topics_id, $start_date, $end_date );
delete from topic_dates where topics_id = ? and start_date = ? and end_date = ?
END

    $c->res->redirect( $c->uri_for( '/admin/tm/edit_dates/' . $topics_id, { status_msg => 'Date deleted.' } ) );
}

# add timespan dates for every $interval days
sub _add_interval_dates
{
    my ( $db, $topic, $interval ) = @_;

    return unless ( $interval > 0 );

    sub increment_day { MediaWords::Util::SQL::increment_day( @_ ) }

    my $last_interval_start = increment_day( $topic->{ end_date }, -1 * $interval );

    for ( my $i = $topic->{ start_date } ; $i lt $last_interval_start ; $i = increment_day( $i, $interval ) )
    {
        _add_topic_date( $db, $topic, $i, increment_day( $i, $interval ) );
    }
}

# add custom timespan range to topic_dates
sub add_date : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', $topics_id );

    my $interval   = $c->req->params->{ interval } + 0;
    my $start_date = $c->req->params->{ start_date };
    my $end_date   = $c->req->params->{ end_date };

    if ( $interval )
    {
        _add_interval_dates( $db, $topic, $interval );
    }
    else
    {
        my $valid_date = qr/^\d\d\d\d-\d\d-\d\d$/;
        if ( !( ( $start_date =~ $valid_date ) && ( $end_date =~ $valid_date ) ) )
        {
            $c->res->redirect(
                $c->uri_for( '/admin/tm/edit_dates/' . $topics_id, { error_msg => 'Invalid date format.' } ) );
            return;
        }

        die( "missing start_date or end_date" ) unless ( $start_date && $end_date );

        _add_topic_date( $db, $topic, $start_date, $end_date );
    }

    $c->res->redirect( $c->uri_for( '/admin/tm/edit_dates/' . $topics_id, { status_msg => 'Dates added.' } ) );
}

# edit list of topic_dates for the topic
sub edit_dates : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $db = $c->dbis;

    my $topic = $db->find_by_id( 'topics', $topics_id ) || die( "Unable to find topic" );

    my $topic_dates = $db->query( <<END, $topics_id )->hashes;
select td.* from topic_dates td where td.topics_id = ? order by td.start_date, td.end_date desc
END

    $c->stash->{ topic }       = $topic;
    $c->stash->{ topic_dates } = $topic_dates;
    $c->stash->{ template }    = 'tm/edit_dates.tt2';
}

# find existing media_type_tag_set for topic or create a new one
# if one does not already exist
sub _find_or_create_topic_media_type
{
    my ( $db, $topic ) = @_;

    if ( my $tag_sets_id = $topic->{ media_type_tag_sets_id } )
    {
        return $db->find_by_id( 'tag_sets', $tag_sets_id );
    }

    my $tag_set = {
        name        => "topic_" . $topic->{ topics_id } . "_media_types",
        label       => "Media Types for " . $topic->{ name } . " Topic",
        description => "These tags are media types specific to the " . $topic->{ name } . " topic"
    };

    $tag_set = $db->create( 'tag_sets', $tag_set );

    my $not_typed_tag = {
        tag         => 'Not Typed',
        label       => 'Not Typed',
        description => 'Choose to indicate that this medium should be typed according to its universal type in this topic',
        tag_sets_id => $tag_set->{ tag_sets_id }
    };

    $db->create( 'tags', $not_typed_tag );

    $db->query( <<END, $tag_set->{ tag_sets_id }, $topic->{ topics_id } );
update topics set media_type_tag_sets_id = ? where topics_id = ?
END

    return $tag_set;
}

# add a new media type tag
sub add_media_type : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $form = $c->create_form( { load_config_file => $c->path_to() . '/root/forms/admin/tm/topic_media_type.yml' } );

    my $db = $c->dbis;

    my $topic = $db->find_by_id( 'topics', $topics_id ) || die( "Unable to find topic" );

    $c->stash->{ topic }    = $topic;
    $c->stash->{ form }     = $form;
    $c->stash->{ template } = 'tm/add_media_type.tt2';

    $form->process( $c->request );

    return unless ( $form->submitted_and_valid );

    my $p = $form->params;

    my $tag_set = _find_or_create_topic_media_type( $db, $topic );

    my $tag = {
        tag         => $p->{ tag },
        label       => $p->{ label },
        description => $p->{ description },
        tag_sets_id => $tag_set->{ tag_sets_id }
    };

    $db->create( 'tags', $tag );

    my $status_msg = "Media type has been created.";
    $c->res->redirect( $c->uri_for( "/admin/tm/edit_media_types/$topic->{ topics_id }", { status_msg => $status_msg } ) );
}

# delete a single media type
sub delete_media_type : Local
{
    my ( $self, $c, $tags_id ) = @_;

    my $db = $c->dbis;

    my $tag = $db->find_by_id( 'tags', $tags_id ) || die( "Unable to find tag" );

    my $topic = $db->query( <<END, $tag->{ tag_sets_id } )->hash;
select * from topics where media_type_tag_sets_id = ?
END

    die( "Unable to find topic" ) unless ( $topic );

    $c->dbis->query( "delete from tags where tags_id = ?", $tags_id );

    my $status_msg = "Media type has been deleted.";
    $c->res->redirect( $c->uri_for( "/admin/tm/edit_media_types/$topic->{ topics_id }", { status_msg => $status_msg } ) );
}

# edit single topic media type tag
sub edit_media_type : Local
{
    my ( $self, $c, $tags_id ) = @_;

    my $form = $c->create_form( { load_config_file => $c->path_to() . '/root/forms/admin/tm/topic_media_type.yml' } );

    my $db = $c->dbis;

    my $tag = $db->find_by_id( 'tags', $tags_id ) || die( "Unable to find tag" );

    my $topic = $db->query( <<END, $tag->{ tag_sets_id } )->hash;
select * from topics where media_type_tag_sets_id = ?
END

    die( "Unable to find topic" ) unless ( $topic );

    $form->default_values( $tag );
    $form->process( $c->req );

    if ( !$form->submitted_and_valid )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ topic }    = $topic;
        $c->stash->{ tag }      = $tag;
        $c->stash->{ template } = 'tm/edit_media_type.tt2';
        return;
    }

    my $p = $form->params;

    $tag->{ tag }         = $p->{ tag };
    $tag->{ label }       = $p->{ label };
    $tag->{ description } = $p->{ description };

    $c->dbis->update_by_id( 'tags', $tags_id, $tag );

    my $topics_id = $topic->{ topics_id };
    $c->res->redirect( $c->uri_for( "/admin/tm/edit_media_types/$topics_id", { status_msg => 'Media type updated.' } ) );
}

# edit list of topic specific media types
sub edit_media_types : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $db = $c->dbis;

    my $topic = $db->find_by_id( 'topics', $topics_id ) || die( "Unable to find topic" );

    my $media_types = $db->query( <<END, $topics_id )->hashes;
select t.*
    from tags t
        join topics c on ( c.media_type_tag_sets_id = t.tag_sets_id )
    where
        c.topics_id = ?
    order by t.tag
END

    $c->stash->{ topic }       = $topic;
    $c->stash->{ media_types } = $media_types;
    $c->stash->{ template }    = 'tm/edit_media_types.tt2';
}

# get a simple count of stories that belong to each partisan media collection
sub _get_partisan_counts
{

    my ( $db, $stories_ids ) = @_;

    my $stories_clause = '1=1';
    if ( $stories_ids )
    {
        $stories_ids = [ map { int( $_ ) } @{ $stories_ids } ];

        my $ids_table = $db->get_temporary_ids_table( $stories_ids );
        $stories_clause = "s.stories_id in ( select id from $ids_table )";
    }

    my $query = <<END;
-- partisan collection tags
with partisan_tags as (
    select t.*
        from
            tags t
            join tag_sets ts on (t.tag_sets_id = ts.tag_sets_id )
        where
            ts.name = 'collection' and
            t.tag in ( 'partisan_2012_liberal', 'partisan_2012_conservative', 'partisan_2012_libertarian' )
),

-- all stories in the topic belonging to the media tagged with one of the partisan collection tags
partisan_stories as (
    select s.*, t.*
        from
            snapshot_stories s
            join snapshot_media_tags_map mtm on ( s.media_id = mtm.media_id )
            join snapshot_tags t on ( mtm.tags_id = t.tags_id )
            join partisan_tags pt on ( t.tags_id = pt.tags_id )
            join snapshot_tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
        where
            $stories_clause
)

select
        ps.tag,
        ps.label,
        count(*) as num_stories
    from partisan_stories ps
    group by ps.tags_id, ps.tag, ps.label
    order by count(*) desc
END

    return $db->query( $query )->hashes;
}

# various stats about an enumerated list of stories
sub story_stats : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $timespans_id = $c->req->params->{ timespan };
    my ( $timespan, $cd, $topic ) = _get_topic_objects( $db, $timespans_id );

    my $title = $c->req->params->{ title };
    my $live  = $c->req->params->{ l };
    my $q     = $c->req->params->{ q };

    my $solr_p = _get_solr_params_for_timespan_query( $timespan, $q );

    my $stories_ids = MediaWords::Solr::search_for_stories_ids( $db, $solr_p );

    my $num_stories = scalar( @{ $stories_ids } );

    $db->begin;

    MediaWords::TM::Snapshot::setup_temporary_snapshot_tables( $db, $timespan, $topic, $live );

    my $media_type_stats = _get_media_type_stats_for_timespan( $db, $stories_ids );
    my $partisan_counts = _get_partisan_counts( $db, $stories_ids );

    # my $partisan_metrics = _get_partisan_link_metrics( $db, $stories_ids );

    $db->commit;

    $c->stash->{ title }            = $title;
    $c->stash->{ timespan }         = $timespan;
    $c->stash->{ snapshot }         = $cd;
    $c->stash->{ topic }            = $topic;
    $c->stash->{ media_type_stats } = $media_type_stats;
    $c->stash->{ partisan_counts }  = $partisan_counts;
    $c->stash->{ num_stories }      = $num_stories;
    $c->stash->{ live }             = $live;
    $c->stash->{ template }         = 'tm/story_stats.tt2';
}

# create a new focus definition within the 'Queries' focal set definition
sub _create_focus_definition
{
    my ( $db, $topic, $p ) = @_;

    eval { MediaWords::Solr::query( $db, { q => $p->{ query }, rows => 0 } ) };
    die( "invalid solr query: $@" ) if ( $@ );

    my $fsd = $db->query( <<SQL, $topic->{ topics_id } )->hash;
select * from focal_set_definitions where topics_id = ? and name = 'Queries'
SQL

    if ( !$fsd )
    {
        $fsd = { topics_id => $topic->{ topics_id }, name => 'Queries', focal_technique => 'Boolean Query' };
        $fsd = $db->create( 'focal_set_definitions', $fsd );
    }

    my $fd = $db->query( <<SQL, $fsd->{ focal_set_definitions_id }, $p->{ name }, $p->{ query } )->hash;
insert into focus_definitions ( focal_set_definitions_id, name, arguments )
    values( \$1, \$2, ( '{ "query": ' || to_json( \$3::text ) || ' }' )::json )
    returning *
SQL

    return $fd;
}

# add a new focus
sub add_focus : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $form = $c->create_form( { load_config_file => $c->path_to() . '/root/forms/admin/tm/focus.yml' } );

    my $db = $c->dbis;

    my $topic = $db->find_by_id( 'topics', $topics_id ) || die( "Unable to find topic" );

    $c->stash->{ topic }    = $topic;
    $c->stash->{ form }     = $form;
    $c->stash->{ template } = 'tm/add_focus.tt2';

    $form->process( $c->request );

    return unless ( $form->submitted_and_valid );

    my $p            = $form->params;
    my $redirect_url = "/admin/tm/edit_foci/$topic->{ topics_id }";

    my $focus = $db->query( <<SQL, $topics_id, $p->{ name } )->hash;
select *
    from focus_definitions fd
        join focal_set_definitions fsd using ( focal_set_definitions_id )
    where fsd.topics_id = ? and lower( fd.name ) = lower( ? )
SQL

    if ( $focus )
    {
        return $c->res->redirect( $redirect_url, { error_msg => "Focus with the name '$p->{ name }' already exists." } );
    }

    _create_focus_definition( $db, $topic, $p );

    $c->res->redirect( $c->uri_for( $redirect_url, { status_msg => "Focus has been created." } ) );
}

# delete a single media type
sub delete_focus : Local
{
    my ( $self, $c, $focus_definitions_id ) = @_;

    my $db = $c->dbis;

    my $fd  = $db->require_by_id( 'focus_definitions',     $focus_definitions_id );
    my $fsd = $db->require_by_id( 'focal_set_definitions', $fd->{ focal_set_definitions_id } );

    $db->begin;

    # this will fail and generate an error if there are any non empty timespans, which
    # is fine because the ui shouldn't allow the user to call on a query that has any non-empty timespans
    $db->delete_by_id( "focus_definitions", $focus_definitions_id );
    $db->commit;

    my $status_msg = "Focus has been deleted.";
    $c->res->redirect( $c->uri_for( "/admin/tm/edit_foci/$fsd->{ topics_id }", { status_msg => $status_msg } ) );
}

# get the focus definitions for the given topic
sub _get_focus_definitions ($$)
{
    my ( $db, $topic ) = @_;

    my $focus_definitions = $db->query( <<SQL, $topic->{ topics_id } )->hashes;
select fd.*
    from focus_definitions fd
        join focal_set_definitions fsd using ( focal_set_definitions_id )
    where fsd.topics_id = ?
    order by name
SQL

    return $focus_definitions;
}

# edit list of topic specific media types
sub edit_foci : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $db = $c->dbis;

    my $topic = $db->require_by_id( 'topics', $topics_id );

    my $focus_definitions = _get_focus_definitions( $db, $topic );

    $c->stash->{ topic }             = $topic;
    $c->stash->{ focus_definitions } = $focus_definitions;
    $c->stash->{ template }          = 'tm/edit_foci.tt2';
}

# enqueue a mining job
sub mine : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $db = $c->dbis;

    my $topic = $db->find_by_id( 'topics', $topics_id ) || die( "Unable to find topic" );

    MediaWords::TM::add_to_mine_job_queue( $db, $topic );

    my $status = 'Topic spidering job queued.';
    $c->res->redirect( $c->uri_for( "/admin/tm/view/" . $topics_id, { status_msg => $status } ) );

    return;
}

sub mining_status : Local
{
    my ( $self, $c, $topics_id ) = @_;

    my $db = $c->dbis;

    my $topic = $db->find_by_id( 'topics', $topics_id ) || die( "Unable to find topic" );

    my $mining_status = _get_mining_status( $db, $topic );

    $c->stash->{ topic }         = $topic;
    $c->stash->{ mining_status } = $mining_status;
    $c->stash->{ template }      = 'tm/mining_status.tt2';
}

1;
