package MediaWords::GearmanFunction::Bitly::AggregateStoryStats;

#
# Use story's click / referrer counts stored in GridFS to fill up aggregated stats table
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/Bitly/AggregateStoryStats.pm
#

use strict;
use warnings;

use Moose;

# Don't log each and every extraction job into the database
with 'Gearman::JobScheduler::AbstractFunction';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::GearmanJobSchedulerConfiguration;
use MediaWords::Util::Bitly;
use MediaWords::Util::URL;
use Readonly;
use Data::Dumper;

# Having a global database object should be safe because
# Gearman::JobScheduler's workers don't support fork()s anymore
my $db = undef;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    # Postpone connecting to the database so that compile test doesn't do that
    $db ||= MediaWords::DB::connect_to_db();

    my $stories_id = $args->{ stories_id } or die "'stories_id' is not set.";

    say STDERR "Aggregating story stats for story $stories_id...";

    my $story = $db->find_by_id( 'stories', $stories_id );
    unless ( $story )
    {
        die "Unable to find story $stories_id.";
    }

    my $stats = MediaWords::Util::Bitly::read_story_stats( $db, $stories_id );
    unless ( defined $stats )
    {
        die "Stats for story $stories_id is undefined; perhaps story is not (yet) processed with Bit.ly?";
    }
    unless ( ref( $stats ) eq ref( {} ) )
    {
        die "Stats for story $stories_id is not a hashref.";
    }

    # {
    #     timestamp => click_count,
    #     ...
    # }
    my $click_counts = {};

    # {
    #     start_timestamp => {
    #         end_timestamp => referrer_count,
    #         ...
    #     },
    #     ...
    # }
    my $referrer_counts = {};

    # Aggregate stats
    if ( $stats->{ 'error' } )
    {
        if ( $stats->{ 'error' } eq 'NOT_FOUND' )
        {
            say STDERR "Story $stories_id was not found on Bit.ly, so click / referrer count is 0.";
        }
        else
        {
            die "Story $stories_id has encountered unknown error while collecting Bit.ly stats: " . $stats->{ 'error' };
        }
    }
    else
    {
        my $stories_original_url             = $story->{ url };
        my $stories_original_url_is_homepage = MediaWords::Util::URL::is_homepage_url( $stories_original_url );

        unless ( $stats->{ 'data' } )
        {
            die "'data' is not set for story's $stories_id stats hashref.";
        }

        foreach my $bitly_id ( keys %{ $stats->{ 'data' } } )
        {
            my $bitly_data = $stats->{ 'data' }->{ $bitly_id };

            # If URL gets redirected to the homepage (e.g.
            # http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/ leads
            # to http://www.wired.com/), don't use those redirects
            my $url = $bitly_data->{ 'url' };
            unless ( $stories_original_url_is_homepage )
            {
                if ( MediaWords::Util::URL::is_homepage_url( $url ) )
                {
                    say STDERR "URL $stories_original_url got redirected to $url which " .
                      "looks like a homepage, so I'm skipping that.";
                    next;
                }
            }

            # Click count (indiscriminate from date range)
            unless ( $bitly_data->{ 'clicks' } )
            {
                die "Bit.ly stats hashref doesn't have 'clicks' key for Bit.ly ID $bitly_id, story $stories_id.";
            }
            foreach my $bitly_clicks ( @{ $bitly_data->{ 'clicks' } } )
            {
                foreach my $link_clicks ( @{ $bitly_clicks->{ 'link_clicks' } } )
                {
                    my $link_clicks_timestamp = $link_clicks->{ 'dt' } + 0;
                    my $link_clicks_count     = $link_clicks->{ 'clicks' } + 0;

                    unless ( defined $click_counts->{ $link_clicks_timestamp } )
                    {
                        $click_counts->{ $link_clicks_timestamp } = 0;
                    }
                    $click_counts->{ $link_clicks_timestamp } += $link_clicks_count;
                }
            }

            # Referrer count (indiscriminate from date range)
            unless ( $bitly_data->{ 'referrers' } )
            {
                die "Bit.ly stats hashref doesn't have 'referrers' key for Bit.ly ID $bitly_id, story $stories_id.";
            }
            foreach my $bitly_referrers ( @{ $bitly_data->{ 'referrers' } } )
            {
                unless ( defined $bitly_referrers->{ 'unit_reference_ts' } )
                {
                    die "Bit.ly stats hashref doesn't have 'referrers/unit_reference_ts' key " .
                      "for Bit.ly ID $bitly_id, story $stories_id.";
                }
                unless ( defined $bitly_referrers->{ 'unit' } )
                {
                    die "Bit.ly stats hashref doesn't have 'referrers/unit' key " .
                      "for Bit.ly ID $bitly_id, story $stories_id.";
                }
                unless ( defined $bitly_referrers->{ 'units' } )
                {
                    die "Bit.ly stats hashref doesn't have 'referrers/units' key " .
                      "for Bit.ly ID $bitly_id, story $stories_id.";
                }
                unless ( defined $bitly_referrers->{ 'tz_offset' } )
                {
                    die "Bit.ly stats hashref doesn't have 'referrers/tz_offset' key " .
                      "for Bit.ly ID $bitly_id, story $stories_id.";
                }
                unless ( $bitly_referrers->{ 'unit' } eq 'day' )
                {
                    die "Bit.ly stats hashref's 'referrers/unit' is not equal to 'day' " .
                      "for Bit.ly ID $bitly_id, story $stories_id.";
                }
                unless ( $bitly_referrers->{ 'tz_offset' } == 0 )
                {
                    die "Bit.ly stats hashref's 'referrers/unit' is not equal to 'day' " .
                      "for Bit.ly ID $bitly_id, story $stories_id.";
                }

                my $referrer_end_timestamp = $bitly_referrers->{ 'unit_reference_ts' };
                my $referrer_start_timestamp =
                  $referrer_end_timestamp - ( ( $bitly_referrers->{ 'units' } - 1 ) * 24 * 60 * 60 );
                my $referrer_count = scalar( @{ $bitly_referrers->{ 'referrers' } } );

                unless ( defined $referrer_counts->{ $referrer_start_timestamp } )
                {
                    $referrer_counts->{ $referrer_start_timestamp } = {};
                }
                unless ( defined $referrer_counts->{ $referrer_start_timestamp }->{ $referrer_end_timestamp } )
                {
                    $referrer_counts->{ $referrer_start_timestamp }->{ $referrer_end_timestamp } = 0;
                }
                $referrer_counts->{ $referrer_start_timestamp }->{ $referrer_end_timestamp } += $referrer_count;
            }
        }
    }

    # say STDERR "Story's $stories_id click counts: " . Dumper($click_counts);
    # say STDERR "Story's $stories_id referrer counts: " . Dumper($referrer_counts);

    # Store stats
    foreach my $click_timestamp ( sort keys %{ $click_counts } )
    {
        my $click_count = $click_counts->{ $click_timestamp };

        $db->query(
            <<EOF,
            SELECT upsert_bitly_story_daily_clicks(
                ?,
                (TO_TIMESTAMP(?) AT TIME ZONE 'GMT')::date,
                ?
            )
EOF
            $stories_id, $click_timestamp, $click_count
        );
    }
    foreach my $referrer_start_timestamp ( sort keys %{ $referrer_counts } )
    {
        foreach my $referrer_end_timestamp ( sort keys %{ $referrer_counts->{ $referrer_start_timestamp } } )
        {
            my $referrer_count = $referrer_counts->{ $referrer_start_timestamp }->{ $referrer_end_timestamp };

            $db->query(
                <<EOF,
                SELECT upsert_bitly_story_referrers(
                    ?,
                    (TO_TIMESTAMP(?) AT TIME ZONE 'GMT')::date,
                    (TO_TIMESTAMP(?) AT TIME ZONE 'GMT')::date,
                    ?
                )
EOF
                $stories_id, $referrer_start_timestamp, $referrer_end_timestamp, $referrer_count
            );
        }
    }

    # Mark the story as processed
    $db->query(
        <<EOF,
        SELECT upsert_bitly_processed_stories(?)
EOF
        $stories_id
    );

    say STDERR "Done aggregating story stats for story $stories_id.";
}

# write a single log because there are a lot of Bit.ly processing jobs so it's
# impractical to log each job into a separate file
sub unify_logs()
{
    return 1;
}

# Returns true if two or more jobs with the same parameters can not be run at
# the same and instead should be merged into one.
sub unique()
{
    # If the "AggregateStoryStats" job is already waiting in the queue for a
    # given story, a new one has to be enqueued right after it in order to
    # update data with new controversy's start / end dates.
    #
    # Thus, the worker is *NOT* unique.
    return 0;
}

# (Gearman::JobScheduler::AbstractFunction implementation) Return default configuration
sub configuration()
{
    return MediaWords::Util::GearmanJobSchedulerConfiguration->instance;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
