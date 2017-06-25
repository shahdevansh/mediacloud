package MediaWords::TM::Model;

# code to generate models of timespans based on validation
# data about date, link extraction, and duplication error rates

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use List::Util;
use POSIX;
use Statistics::Basic;
use Readonly;

use MediaWords::TM::Snapshot;
use MediaWords::Util::Config;
use MediaWords::Util::SQL;
use MediaWords::Util::Tags;

# percentage of media sources in a given snapshot for which to generate a confidence interval
Readonly my $MODEL_PERCENT_TOP_MEDIA => 10;

# percentage of guessed dates that are misdated
Readonly my $PERCENT_DATE_MISDATED => 22;

# percentages that a wrong date is wrong by the given number of days
Readonly my $PERCENT_DATE_WRONG_BY_1    => 0;
Readonly my $PERCENT_DATE_WRONG_BY_3    => 25;
Readonly my $PERCENT_DATE_WRONG_BY_7    => 0;
Readonly my $PERCENT_DATE_WRONG_BY_MORE => 75;

# percent of stories guessed to be undateable that are actually dateable
Readonly my $PERCENT_UNDATEABLE_DATE_DATEABLE => 30;

# percent of stories guessed to be dateable that are actually undateable
Readonly my $PERCENT_DATE_UNDATEABLE => 13;

# get the top $MODEL_PERCENT_TOP_MEDIA of media sources from the current snapshot by incoming links
sub get_top_media_link_counts
{
    my ( $db, $timespan, $size_factor ) = @_;

    my ( $num_media ) = $db->query( "select count(*) from snapshot_medium_link_counts" )->flat;

    return [] unless ( $num_media > 0 );

    my $num_top_media = POSIX::ceil( $num_media * ( $MODEL_PERCENT_TOP_MEDIA / 100 ) );
    $num_top_media *= $size_factor if ( $size_factor );

    my $top_media = $db->query( <<END, $num_top_media + 1 )->hashes;
select * from snapshot_medium_link_counts order by media_inlink_count desc limit ?
END

    # the last medium included must have more inlinks than the first medium not included
    my $first_miss_medium = pop( @{ $top_media } );
    my $min_inlink_count  = $first_miss_medium->{ inlink_count } + 1;
    my $pruned_top_media  = [ grep { $_->{ inlink_count } > $min_inlink_count } @{ $top_media } ];

    return $pruned_top_media;
}

# change a dateable story to an undateable one
sub tweak_dateable_story
{
    my ( $db, $timespan, $story ) = @_;

    TRACE "tweak_dateable_story: $story->{ stories_id }";

    my $undateable_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_invalid:undateable' );

    $db->query( <<END, $story->{ stories_id }, $undateable_tag->{ tags_id } );
insert into snapshot_stories_tags_map
    ( stories_id, tags_id )
    values ( ?, ? )
END

}

# get random sample of stories with guessed dates according to $percent_sample
sub sample_guessed_date_stories
{
    my ( $db, $timespan, $percent_sample ) = @_;

    my $stories = $db->query( <<END, $percent_sample )->hashes;
select * from
(
    select s.*
        from snapshot_stories s, snapshot_tags t, snapshot_tag_sets ts, snapshot_stories_tags_map stm
        where s.stories_id = stm.stories_id and
            t.tags_id = stm.tags_id and
            t.tag_sets_id = ts.tag_sets_id and
            ts.name = 'date_guess_method' and
            t.tag not in ( 'manual', 'merged_story_rss', 'guess_by_url_and_date_text', 'guess_by_url' )

    except

    select s.*
        from snapshot_stories s, snapshot_tags t, snapshot_tag_sets ts, snapshot_stories_tags_map stm
        where s.stories_id = stm.stories_id and
            t.tags_id = stm.tags_id and
            t.tag_sets_id = ts.tag_sets_id and
            ts.name = 'date_invalid' and
            t.tag = 'undateable'
) q
    where ( random() *  100 ) < ?
END

    return $stories;
}

# change dated stories to be undateable based on our data on how many
# dated stories are undateable
sub tweak_dateable_stories
{
    my ( $db, $timespan ) = @_;

    my $stories = sample_guessed_date_stories( $db, $timespan, $PERCENT_DATE_UNDATEABLE );

    map { tweak_dateable_story( $db, $timespan, $_ ) } @{ $stories };
}

# change an undateable story to a dateable one by deleting the date_guess_method:undateable tag
sub tweak_undateable_story
{
    my ( $db, $timespan, $story ) = @_;

    TRACE "tweak_undateable_story: $story->{ stories_id }";

    $db->query( <<END, $story->{ stories_id } );
delete from snapshot_stories_tags_map stm
    using snapshot_tags t, snapshot_tag_sets ts
    where stm.stories_id = ? and
        stm.tags_id = t.tags_id and
        t.tag_sets_id = ts.tag_sets_id and
        ts.name = 'date_invalid' and
        t.tag = 'undateable'
END
}

# change undateable stories to dateable ones according to our data
# on how many undateable stories are really dateable
sub tweak_undateable_stories
{
    my ( $db, $timespan ) = @_;

    my $stories = $db->query( <<END, $PERCENT_UNDATEABLE_DATE_DATEABLE )->hashes;
select * from
(
    select s.*
        from snapshot_stories s, snapshot_tags t, snapshot_tag_sets ts, snapshot_stories_tags_map stm
        where s.stories_id = stm.stories_id and
            t.tags_id = stm.tags_id and
            t.tag_sets_id = ts.tag_sets_id and
            ts.name = 'date_invalid' and
            t.tag = 'undateable'

    except

    select s.*
        from snapshot_stories s, snapshot_tags t, snapshot_tag_sets ts, snapshot_stories_tags_map stm
        where s.stories_id = stm.stories_id and
            t.tags_id = stm.tags_id and
            t.tag_sets_id = ts.tag_sets_id and
            ts.name = 'date_guess_method' and
            t.tag = 'manual'
) q
    where ( random() *  100 ) < ?

END

    map { tweak_undateable_story( $db, $timespan, $_ ) } @{ $stories };
}

# get the new story date according to our validation data of how dates
# are typically wrong
sub get_tweaked_story_date
{
    my ( $old_date ) = @_;

    my $past = ( rand( 2 ) < 1 ) ? -1 : 1;

    # roll a die to see how wrong the date is, according to stats about wrong date distribution
    my $wrong_by_dist = rand( 100 );

    my $new_date;
    if ( $wrong_by_dist < $PERCENT_DATE_WRONG_BY_1 )
    {
        return MediaWords::Util::SQL::increment_day( $old_date, $past );
    }
    $wrong_by_dist -= $PERCENT_DATE_WRONG_BY_1;

    if ( $wrong_by_dist < $PERCENT_DATE_WRONG_BY_3 )
    {
        my $days = POSIX::ceil( rand( 2 ) ) + 1;
        return MediaWords::Util::SQL::increment_day( $old_date, $past * $days );
    }
    $wrong_by_dist -= $PERCENT_DATE_WRONG_BY_3;

    if ( $wrong_by_dist < $PERCENT_DATE_WRONG_BY_7 )
    {
        my $days = POSIX::ceil( rand( 4 ) ) + 3;
        return MediaWords::Util::SQL::increment_day( $old_date, $past * $days );
    }

    my $days = POSIX::ceil( rand( 53 ) + 7 );
    return MediaWords::Util::SQL::increment_day( $old_date, $past * $days );
}

# change the story date according to our validation data of how dates are
# typically wrong
sub tweak_story_date
{
    my ( $db, $timespan, $story ) = @_;

    my $new_date = get_tweaked_story_date( $story->{ publish_date } );

    TRACE "tweak story: $story->{ stories_id } $story->{ publish_date } -> $new_date";

    $db->query( <<END, $new_date, $story->{ stories_id } );
update snapshot_stories set publish_date = ? where stories_id = ?
END

}

# chagne the dates of stories according to our data of how often guess dates
# are wrong
sub tweak_misdated_stories
{
    my ( $db, $timespan ) = @_;

    my $stories = sample_guessed_date_stories( $db, $timespan, $PERCENT_DATE_MISDATED );

    map { tweak_story_date( $db, $timespan, $_ ) } @{ $stories };
}

# change the dates in the current snapshot to model the accuracy data form our validation tests
sub tweak_story_dates
{
    my ( $db, $timespan ) = @_;

    tweak_misdated_stories( $db, $timespan );
    tweak_undateable_stories( $db, $timespan );
    tweak_dateable_stories( $db, $timespan );
}

# generate a single model of the snapshot for the current timespan, tweaking
# various aspects of the data according to our validation numbers (for example
# changing X% of dates because we know that in general X% of our dates are wrong).
# Return an ordered list of the top media sources by incoming links.
sub model_confidence_data
{
    my ( $db, $timespan ) = @_;

    if ( $db->in_transaction() )
    {
        die "model confidence data cannot be called within an ongoing transaction";
    }

    $db->begin;

    tweak_story_dates( $db, $timespan );

    MediaWords::TM::Snapshot::generate_timespan_data( $db, $timespan, 1 );

    my $top_media_link_counts = get_top_media_link_counts( $db, $timespan, 2 );

    $db->rollback;

    return $top_media_link_counts;
}

# given an ordered list of medium_counts, return a hash with the media_id of each
# as the key and the order in the list as the value
sub get_medium_count_ranks
{
    my ( $media_counts ) = @_;

    my $ranks = {};
    for ( my $i = 0 ; $i < @{ $media_counts } ; $i++ )
    {
        $ranks->{ $media_counts->[ $i ]->{ media_id } } = $i;
    }

    return $ranks;
}

# return true if the two ranks are within an arbitrary error interval of each other.  Assume a max
# rank of $max_rank for the $model_rank.
sub model_rank_within_error_interval
{
    my ( $clean_rank, $model_rank ) = @_;

    return 0 unless ( defined( $model_rank ) );

    my $interval = POSIX::ceil( $clean_rank / 3 ) + 2;

    return ( abs( $clean_rank - $model_rank ) <= $interval );
}

# given the size of two vectors and the r, return the p value for the correlation
sub get_model_correlation_p_value
{
    my ( $clean_vector, $model_vector, $r ) = @_;

    my $p_hits   = 0;
    my $num_reps = 10000;
    for my $i ( 1 .. $num_reps )
    {
        my $randomized_model = [ List::Util::shuffle( @{ $model_vector } ) ];

        my $p_r = Statistics::Basic::correlation( $clean_vector, $randomized_model );

        $p_hits++ if ( $p_r >= $r );
    }

    return ( $p_hits / $num_reps );
}

# generate and store the mean and sd of the correlations between the ranks
# of the top media of the clean data and of each of the models
sub update_model_correlation
{
    my ( $db, $timespan, $all_models_top_media ) = @_;

    my $clean_top_media = get_top_media_link_counts( $db, $timespan );

    MediaWords::TM::Snapshot::update_timespan( $db, $timespan, 'model_num_media', scalar( @{ $clean_top_media } ) );

    return unless ( @{ $clean_top_media } > 1 && $all_models_top_media );

    my $clean_vector = [];
    for ( my $i = 0 ; $i < @{ $clean_top_media } ; $i++ )
    {
        push( @{ $clean_vector }, $i );
    }

    my $model_r2s = [];
    for my $model_top_media ( @{ $all_models_top_media } )
    {
        my $model_medium_ranks = get_medium_count_ranks( $model_top_media );
        my $model_vector       = [];
        for my $clean_top_medium ( @{ $clean_top_media } )
        {
            my $model_medium_rank = $model_medium_ranks->{ $clean_top_medium->{ media_id } };
            $model_medium_rank = scalar( @{ $model_top_media } + 1 ) unless ( defined( $model_medium_rank ) );
            push( @{ $model_vector }, $model_medium_rank );
        }

        my $r = Statistics::Basic::correlation( $clean_vector, $model_vector );
        push( @{ $model_r2s }, $r * $r );
    }

    my $r2_mean   = Statistics::Basic::mean( $model_r2s ) + 0.00;
    my $r2_stddev = Statistics::Basic::stddev( $model_r2s ) + 0.00;

    MediaWords::TM::Snapshot::update_timespan( $db, $timespan, 'model_r2_mean',   $r2_mean );
    MediaWords::TM::Snapshot::update_timespan( $db, $timespan, 'model_r2_stddev', $r2_stddev );
}

# return text output describing how the models matched (or didn't) with the clean data
sub print_model_matches
{
    my ( $db, $timespan, $all_models_top_media ) = @_;

    my $clean_top_media = get_top_media_link_counts( $db, $timespan );
    my $clean_medium_ranks = get_medium_count_ranks( $clean_top_media );

    INFO "evaluating models ...";

    my $num_model_matches = 0;
    for my $model_top_media ( @{ $all_models_top_media } )
    {
        my $match              = 1;
        my $model_medium_ranks = get_medium_count_ranks( $model_top_media );
        while ( my ( $clean_media_id, $clean_rank ) = each( %{ $clean_medium_ranks } ) )
        {
            my $model_rank = $model_medium_ranks->{ $clean_media_id };
            if ( model_rank_within_error_interval( $clean_rank, $model_rank ) )
            {
                INFO "+";
            }
            else
            {
                my $model_rank_display = defined( $model_rank ) ? $model_rank : 'NA';
                INFO "- [ $clean_media_id: $clean_rank / $model_rank_display ]";
                $match = 0;
            }
        }

        $num_model_matches++ if ( $match );
    }

    # update_timespan( $db, $timespan, 'confidence', $num_model_matches );
    #
    # return $num_model_matches;
}

# run $config->{ mediawords }->{ topic_model_reps } models and return a list of ordered lists
# of top_media, one list of top media for each model run
sub get_all_models_top_media ($$)
{
    my ( $db, $timespan ) = @_;

    my $config = MediaWords::Util::Config::get_config;
    my $model_reps = $config->{ mediawords }->{ topic_model_reps } || 0;

    $model_reps //= 10;

    return undef unless ( $model_reps );

    # these make the data tweaking process and other operations much faster
    $db->query( 'CREATE INDEX IF NOT EXISTS snapshot_stories_story ON snapshot_stories ( stories_id )' );
    $db->query( 'CREATE INDEX IF NOT EXISTS snapshot_tags_tag ON snapshot_tags ( tags_id )' );
    $db->query( 'CREATE INDEX IF NOT EXISTS snapshot_stories_tags_map_story ON snapshot_stories_tags_map ( stories_id )' );

    print "running models: ";
    my $all_models_top_media = [];
    for my $i ( 1 .. $model_reps )
    {
        my $model_top_media = model_confidence_data( $db, $timespan );

        # MediaWords::TM::Snapshot::restore_temporary_tables( $db );

        return unless ( @{ $model_top_media } );

        push( @{ $all_models_top_media }, $model_top_media );
        print ".";
    }

    return $all_models_top_media;
}

1;
