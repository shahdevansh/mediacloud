package MediaWords::GearmanFunction::Bitly::FetchStoryStats;

#
# Fetch story's click / referrer count statistics via Bit.ly API
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/Bitly/FetchStoryStats.pm
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
use MediaWords::Util::Bitly;
use MediaWords::Util::DateTime;
use MediaWords::Util::Process;
use MediaWords::Util::GearmanJobSchedulerConfiguration;
use MediaWords::GearmanFunction::Bitly::AggregateStoryStats;
use Readonly;
use Data::Dumper;

# What stats to fetch for each story
Readonly my $BITLY_FETCH_CATEGORIES => 0;
Readonly my $BITLY_FETCH_CLICKS     => 1;
Readonly my $BITLY_FETCH_REFERRERS  => 1;
Readonly my $BITLY_FETCH_SHARES     => 0;
Readonly my $stats_to_fetch         => MediaWords::Util::Bitly::StatsToFetch->new(
    $BITLY_FETCH_CATEGORIES,    # "/v3/link/category"
    $BITLY_FETCH_CLICKS,        # "/v3/link/clicks"
    $BITLY_FETCH_REFERRERS,     # "/v3/link/referrers"
    $BITLY_FETCH_SHARES         # "/v3/link/shares"
);

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

    # Fetching MIN(start_date) and MAX(start_date) for all controversies the
    # story belongs to
    say STDERR "Fetching story's $stories_id start and end timestamps...";
    my $timestamps = $db->query(
        <<EOF,
        SELECT
            controversy_stories.stories_id,
            EXTRACT(EPOCH FROM MIN(controversy_dates.start_date)) AS start_timestamp,
            EXTRACT(EPOCH FROM MAX(controversy_dates.end_date)) AS end_timestamp
        FROM controversy_stories
            INNER JOIN controversy_dates
                ON controversy_stories.controversies_id = controversy_dates.controversies_id
               AND controversy_dates.boundary = 't'
        WHERE controversy_stories.stories_id = ?
        GROUP BY controversy_stories.stories_id
        ORDER BY controversy_stories.stories_id
EOF
        $stories_id
    )->hash;
    unless ( $timestamps )
    {
        die "Unable to fetch controversy's start and end timestamps.";
    }
    my $start_timestamp = $timestamps->{ start_timestamp };
    my $end_timestamp   = $timestamps->{ end_timestamp };

    my $now = time();
    if ( $start_timestamp > $now )
    {
        say STDERR "Start timestamp is not set, so I will use current timestamp $now as start date.";
        $start_timestamp = $now;
    }
    if ( $end_timestamp > $now )
    {
        say STDERR "End timestamp is not set, so I will use current timestamp $now as end date.";
        $end_timestamp = $now;
    }
    if ( $start_timestamp >= $end_timestamp )
    {
        die "Start timestamp ($start_timestamp) is bigger or equal to end timestamp ($end_timestamp).";
    }

    say STDERR "Start timestamp: " . gmt_date_string_from_timestamp( $start_timestamp );
    say STDERR "End timestamp: " . gmt_date_string_from_timestamp( $end_timestamp );

    say STDERR "Done fetching story's $stories_id start and end timestamps.";

    say STDERR "Fetching story stats for story $stories_id...";
    my $stats;
    eval {
        $stats =
          MediaWords::Util::Bitly::fetch_story_stats( $db, $stories_id, $start_timestamp, $end_timestamp, $stats_to_fetch );
    };
    if ( $@ )
    {
        my $error_message = $@;
        fatal_error( "Unable to fetch Bit.ly stats: $error_message" );
    }

    unless ( $stats )
    {
        # No point die()ing and continuing with other jobs (didn't recover after rate limiting)
        fatal_error( "Stats for story ID $stories_id is undef." );
    }
    unless ( ref( $stats ) eq ref( {} ) )
    {
        # No point die()ing and continuing with other jobs (something wrong with fetch_story_stats())
        fatal_error( "Stats for story ID $stories_id is not a hashref." );
    }
    say STDERR "Done fetching story stats for story $stories_id.";

    # say STDERR "Stats: " . Dumper( $stats );

    say STDERR "Storing story stats for story $stories_id...";
    eval { MediaWords::Util::Bitly::write_story_stats( $db, $stories_id, $stats ); };
    if ( $@ )
    {
        # No point die()ing and continuing with other jobs (something wrong with the storage mechanism)
        fatal_error( "Error while storing story stats for story $stories_id: $@" );
    }
    say STDERR "Done storing story stats for story $stories_id.";

    # Enqueue aggregating Bit.ly stats
    MediaWords::GearmanFunction::Bitly::AggregateStoryStats->enqueue_on_gearman( { stories_id => $stories_id } );
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
    # If the "FetchStoryStats" job is already waiting in the queue for a given
    # controversy, a new one has to be enqueued right after it in order to
    # fetch story stats with updated start / end timestamps.
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
