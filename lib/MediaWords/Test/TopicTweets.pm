package MediaWords::Test::TopicTweets;

=head1 NAME

MediaWords::Test::TopicTweets - functions to help testing external apis

=cut

use strict;
use warnings;

# test MediaWords::Job::FetchTopicTweets

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use MediaWords::Test::HTTP::HashServer;
use Readonly;
use Test::More;

use MediaWords::TM;
use MediaWords::Job::TM::MineTopic;
use MediaWords::Test::DB;
use MediaWords::Test::Data;
use MediaWords::Test::ExternalAPI;
use MediaWords::Test::Supervisor;
use MediaWords::Util::Config;
use MediaWords::Util::JSON;

# test port for mock api server
Readonly my $PORT => 8899;

# id for valid monitor at CH (valid id needed only if MC_TEST_EXTERNAL_APIS set)
Readonly my $CH_MONITOR_ID => 4488828184;

# this is an estimate of the number of tweets per day included in the ch-posts-$date.json files
# this should not be edited other than to provide a better estimate
Readonly my $MAX_MOCK_TWEETS_PER_DAY => 400;

# number of mocked tweets to return for each day -- edit this up to $MAX_MOCK_TWEETS_PER_DAY to change the size
# of the testing set
Readonly my $MOCK_TWEETS_PER_DAY => 25;

# ratios of tweets to urls and users.  these can be edited to derive the desired ratios for testing
Readonly my $MOCK_TWEETS_PER_URL  => 4;
Readonly my $MOCK_TWEETS_PER_USER => 20;

# max number of days difference between start and end dates for test topic -- this can edited for the desired
# number of days for the locak test
Readonly my $LOCAL_DATE_RANGE => 30;

# these should not be edited
Readonly my $NUM_MOCK_URLS  => int( ( $LOCAL_DATE_RANGE * $MOCK_TWEETS_PER_DAY ) / $MOCK_TWEETS_PER_URL );
Readonly my $NUM_MOCK_USERS => int( ( $LOCAL_DATE_RANGE * $MOCK_TWEETS_PER_DAY ) / $MOCK_TWEETS_PER_USER );

# keep track of a date for each story so that they are consistent
my $_mock_story_dates = {};

# return either 2016-01-01 - 2016-01-10 for external api tests or a 2016-01-01 + $LOCAL_DATE_RANGE - 1 for local tests
sub get_test_date_range()
{
    if ( MediaWords::Job::FetchTopicTweets->_get_ch_api_url() =~ /localhost/ )
    {
        my $end_date = MediaWords::Util::SQL::increment_day( '2016-01-01', $LOCAL_DATE_RANGE - 1 );
        return ( '2016-01-01', $end_date );
    }
    else
    {
        return ( '2016-01-01', '2016-01-30' );
    }
}

# return list of dates to test for
sub get_test_dates()
{
    my ( $start_date, $end_date ) = get_test_date_range();

    my $test_dates = [];
    for ( my $date = $start_date ; $date le $end_date ; $date = MediaWords::Util::SQL::increment_day( $date ) )
    {
        push( @{ $test_dates }, $date );
    }

    return $test_dates;
}

# randomly get one of the rest dates
sub get_random_test_date
{
    my $test_dates = get_test_dates();
    return $test_dates->[ int( rand( @{ $test_dates } ) ) ];
}

# return the JSON in one of the ch-posts-$data.json files, where files are available for 2016-01-0[12345];
# chop out all posts other than the first $MOCK_TWEETS_PER_DAY from each file
sub get_test_data
{
    my ( $date ) = @_;

    if ( $MOCK_TWEETS_PER_DAY > $MAX_MOCK_TWEETS_PER_DAY )
    {
        die( "\$MOCK_TWEETS_PER_DAY must be less than \$MAX_MOCK_TWEETS_PER_DAY" );
    }

    my $epoch_day = ( MediaWords::Util::SQL::get_epoch_from_sql_date( $date ) / 86400 );
    my $file_dates = [ map { "2016-01-0" . $_ } ( 1 .. 5 ) ];

    my $file_date = $file_dates->[ $epoch_day % scalar( @{ $file_dates } ) ];

    my $json = MediaWords::Test::Data::read_test_file( "ch", "ch-posts-$file_date.json" );

    my $data = MediaWords::Util::JSON::decode_json( $json );

    die( "no posts found" ) unless ( $data->{ posts } );

    splice( @{ $data->{ posts } }, $MOCK_TWEETS_PER_DAY );

    return MediaWords::Util::JSON::encode_json( $data );
}

# return a mock ch response to the posts end point.  generate the mock response by sending back data
# from a consistent but semirandom selection of ch-posts-2016-01-0[123456].json and replacing
# the tweet id in each tweet url returned by ch with a new unique id. The unique id is the start_date
# passed into the request plus an iterator that increases for each tweet returned.
sub mock_ch_posts
{
    my ( $params, $cookies ) = @_;

    my $auth       = $params->{ 'auth' }  || LOGDIE( "missing auth param" );
    my $id         = $params->{ 'id' }    || LOGDIE( "missing id param" );
    my $start_date = $params->{ 'start' } || LOGDIE( "missing start param" );
    my $end_date   = $params->{ 'end' }   || LOGDIE( "missing end param" );

    my $expected_end_date = MediaWords::Util::SQL::increment_day( $start_date );
    LOGDIE( "end_date expected to be '$expected_end_date' for mock api" ) unless ( $end_date eq $expected_end_date );

    my $json = get_test_data( $start_date );

    my $data = MediaWords::Util::JSON::decode_json( $json );

    # replace tweets with the epoch of the start date so that we can infer the date of each tweet in
    # mock_twitter_lookup below
    my $i = 0;
    for my $ch_post ( @{ $data->{ posts } } )
    {
        my $new_id = MediaWords::Util::SQL::get_epoch_from_sql_date( $start_date ) + $i++;
        $ch_post->{ url } =~ s/status\/\d+/status\/$new_id/;
    }

    my $new_json = MediaWords::Util::JSON::encode_json( $data );

    my $response = "HTTP/1.1 200 OK\r\n";
    $response .= "Content-Type: application/json\r\n";
    $response .= "\r\n";
    $response .= "$new_json\n";
    return $response;
}

# send a simple text page for use mocking tweet url pages
sub mock_tweet_url
{
    my ( $params, $cookies ) = @_;

    my $id = $params->{ 'id' };

    die( "id param must be specified" ) unless ( defined( $id ) );

    my $publish_date = $_mock_story_dates->{ $id };
    if ( !$publish_date )
    {
        my ( $start_date, $end_date ) = get_test_date_range();
        my $start_date_epoch = MediaWords::Util::SQL::get_epoch_from_sql_date( $start_date );
        my $days_back        = $LOCAL_DATE_RANGE + int( rand( 30 ) );
        $publish_date = Date::Format::time2str( "%B %d, %Y", $start_date_epoch - ( 86400 * $days_back ) );
        $_mock_story_dates->{ $id } ||= $publish_date;
    }

    # just include the date as a literal string and the GuessDate module should find and assign that date to the story
    my $response = "HTTP/1.1 200 OK\r\n";
    $response .= "Content-Type: text/plain\r\n";
    $response .= "\r\n";
    $response .= "Sample page for tweet $id url $publish_date\n";
    return $response;
}

sub mock_twitter_lookup
{
    my ( $params, $cookies ) = @_;

    my $id_list = $params->{ 'id' };

    die( "id param must be specified" ) unless ( $id_list );

    my $ids = [ split( ',', $id_list ) ];

    die( "at least one id must be specified" ) unless ( @{ $ids } );

    die( "all ids must be integers" ) if ( grep { $_ =~ /[^0-9]/ } @{ $ids } );

    my $num_errors = ( scalar( @{ $ids } ) > 10 ) ? 3 : 0;

    # simulate twitter not being able to find some ids, which is typical
    map { pop( @{ $ids } ) } ( 1 .. $num_errors );

    my $tweets = [];
    for my $id ( @{ $ids } )
    {
        # restrict url and user ids to desired number;
        # include randomness so that they urls and users are not nearly collated
        my $url_id  = int( $id * rand() ) % $NUM_MOCK_URLS;
        my $user_id = int( $id * rand() ) % $NUM_MOCK_USERS;

        # we can infer the date from the $id as set in mock_ch_post() above
        my $created_at = Date::Format::time2str( '%a %b %d %H:%M:%S +000000 %Y', $id );

        # 127.0.00000.1 goofiness to generate variations on localhost that will produce separate media in TM::Mine
        my $medium_number = ( $url_id % 10 ) + 1;
        my $test_host = '127.0.' . ( '0' x $medium_number ) . ".1";

        my $test_url = "http://$test_host:$PORT/tweet_url?id=$url_id";

        TRACE( "$id -> $created_at" );

        # all we use is id, text, and created_by, so just test for those
        push(
            @{ $tweets },
            {
                id         => $id,
                text       => "sample tweet for id $id",
                created_at => $created_at,
                user       => { screen_name => "user-$user_id" },
                entities   => { urls => [ { expanded_url => $test_url } ] }
            }
        );
    }

    my $json = MediaWords::Util::JSON::encode_json( $tweets );

    my $response = "HTTP/1.1 200 OK\r\n";
    $response .= "Content-Type: application/json\r\n";
    $response .= "\r\n";
    $response .= "$json\n";
    return $response;
}

# verify that topic_tweet_urls match what's in the tweet JSON data as saved in topic_tweets
sub validate_topic_tweet_urls($$)
{
    my ( $db, $topic ) = @_;

    my $topic_tweets = $db->query( <<SQL, $topic->{ topics_id } )->hashes;
select *
    from topic_tweets tt
        join topic_tweet_days ttd using ( topic_tweet_days_id )
    where
        ttd.topics_id = ?
SQL

    my $num_topic_tweets = scalar( @{ $topic_tweets } );

    my $expected_num_urls = 0;
    for my $topic_tweet ( @{ $topic_tweets } )
    {
        my $data = MediaWords::Util::JSON::decode_json( $topic_tweet->{ data } );
        $expected_num_urls += scalar( @{ $data->{ tweet }->{ entities }->{ urls } } );
    }

    # first sanity check to make sure we got some urls
    my ( $num_urls ) = $db->query( "select count(*) from topic_tweet_urls" )->flat;
    is( $num_urls, $expected_num_urls, "number of urls" );

    my $total_json_urls = 0;
    for my $topic_tweet ( @{ $topic_tweets } )
    {
        my $ch_post = MediaWords::Util::JSON::decode_json( $topic_tweet->{ data } );
        my $expected_urls = [ map { $_->{ expanded_url } } @{ $ch_post->{ tweet }->{ entities }->{ urls } } ];
        $total_json_urls += scalar( @{ $expected_urls } );

        for my $expected_url ( @{ $expected_urls } )
        {
            my $got_url = $db->query( "select * from topic_tweet_urls where url = \$1", $expected_url )->hash;
            ok( $got_url, "found url $expected_url" );
        }
    }

    is( $total_json_urls, $num_urls, "num of urls in JSON vs. num of urls in database" );
}

# validate that snap.story_links is what it should be by rebuilding the topic links directly from the
# ch + twitter JSON data stored in topic_tweets and generating a link list using perl
sub validate_story_links
{
    my ( $db, $topic, $timespan ) = @_;

    my $label = "$timespan->{ period } timespan for $timespan->{ start_date }";

    my $topic_tweets = $db->query( <<SQL, $topic->{ topics_id }, $timespan->{ timespans_id } )->hashes;
select tt.*, date_trunc( 'day', tt.publish_date ) publish_day
    from topic_tweets tt
        join topic_tweet_days ttd using ( topic_tweet_days_id )
        join timespans t on ( t.timespans_id = \$2 )
    where
        ttd.topics_id = \$1 and
        (
            ( t.period = 'overall' ) or
            ( tt.publish_date between t.start_date and t.end_date )
        )
SQL

    my $expected_story_tweet_users = {};
    my $user_stories_lookup        = {};
    for my $topic_tweet ( @{ $topic_tweets } )
    {
        my $data = MediaWords::Util::JSON::decode_json( $topic_tweet->{ data } );
        ok( $data->{ url }, "topic tweet data has url" );

        my $tweet = $data->{ tweet } || next;

        my $user = $tweet->{ user }->{ screen_name };
        my $urls = [ map { $_->{ expanded_url } } @{ $tweet->{ entities }->{ urls } } ];

        for my $url ( @{ $urls } )
        {
            my $stories = $db->query( <<SQL, $topic->{ topics_id }, $url )->hashes;
select s.*
    from stories s
        join topic_seed_urls u using ( stories_id )
        join media m using ( media_id )
        join topic_stories ts using ( stories_id, topics_id )
    where
        u.topics_id = \$1 and
        u.url = \$2 and
        m.name not like '%twitter.com%'
SQL

            for my $story ( @{ $stories } )
            {
                my $stories_id = $story->{ stories_id };

                $expected_story_tweet_users->{ $stories_id }->{ $topic_tweet->{ twitter_user } }++;

                $user_stories_lookup->{ $user }->{ $stories_id }->{ media_id } = $story->{ media_id };
                $user_stories_lookup->{ $user }->{ $stories_id }->{ publish_days }->{ $topic_tweet->{ publish_day } } = 1;
            }
        }
    }

    my $expected_link_lookup = {};
    while ( my ( $user, $stories_lookup ) = each( %{ $user_stories_lookup } ) )
    {
        for my $a ( keys( %{ $stories_lookup } ) )
        {
            my $days_a = [ keys( %{ $stories_lookup->{ $a }->{ publish_days } } ) ];
            for my $b ( keys( %{ $stories_lookup } ) )
            {
                next unless ( grep { $stories_lookup->{ $b }->{ publish_days }->{ $_ } } @{ $days_a } );

                next if ( $stories_lookup->{ $a }->{ media_id } == $stories_lookup->{ $b }->{ media_id } );

                $expected_link_lookup->{ $a }->{ $b }++;
            }
        }
    }

    my $expected_num_links = 0;
    for my $a ( keys( %{ $expected_link_lookup } ) )
    {
        map { $expected_num_links++ } keys( %{ $expected_link_lookup->{ $a } } );
    }

    my $story_links = $db->query( <<SQL, $timespan->{ timespans_id } )->hashes;
select * from snap.story_links where timespans_id = \$1
SQL

    is( scalar( @{ $story_links } ), $expected_num_links, "$label: number of story links" );

    for my $story_link ( @{ $story_links } )
    {
        my $source_stories_id = $story_link->{ source_stories_id };
        my $ref_stories_id    = $story_link->{ ref_stories_id };

        my $valid_link = $expected_link_lookup->{ $source_stories_id }->{ $ref_stories_id };

        ok( $valid_link, "$label: valid story link $source_stories_id -> $ref_stories_id" );
    }

    my $story_link_counts = $db->query( <<SQL, $timespan->{ timespans_id } )->hashes;
select * from snap.story_link_counts where timespans_id = \$1
SQL

    for my $slc ( @{ $story_link_counts } )
    {
        my $stories_id           = $slc->{ stories_id };
        my $expected_tweet_count = scalar( keys( %{ $expected_story_tweet_users->{ $stories_id } } ) );
        is( $slc->{ simple_tweet_count }, $expected_tweet_count, "$label simple tweet count story $stories_id" );
    }
}

# verify the the snapshot has only stories shared the given timespan and links for coshares between tweets during timespan
sub validate_timespan($$$)
{
    my ( $db, $topic, $timespan ) = @_;

    my $timespans_id  = $timespan->{ timespans_id };
    my $timespan_date = $timespan->{ start_date };

    my $label = "$timespan->{ period } timespan for $timespan->{ start_date }";

    my $story_link_counts = $db->query( <<SQL, $timespans_id )->hashes;
select * from snap.story_link_counts where timespans_id = \$1
SQL

    my ( $expected_num_stories ) = $db->query( <<SQL, $topic->{ topics_id }, $timespans_id )->flat;
select count( distinct stories_id )
    from topic_tweet_full_urls ttfu
        join timespans t on ( timespans_id = \$2 )
    where
        (
            ( t.period = 'overall' ) or
            ( ttfu.publish_date between t.start_date and t.end_date )
        ) and
        ttfu.topics_id = \$1
SQL

    ok( $expected_num_stories > 0, "$label: num of stories > 0" );
    is( scalar( @{ $story_link_counts } ), $expected_num_stories, "$label: number of stories" );

    validate_story_links( $db, $topic, $timespan );
}

# verify that the data in each of the  snapshots is correct
sub validate_timespans($$)
{
    my ( $db, $topic ) = @_;

    my $timespans = $db->query( <<SQL, $topic->{ topics_id } )->hashes;
select t.*
    from timespans  t
        join snapshots s using ( snapshots_id )
    where
        topics_id = \$1
    order by start_date
SQL

    map { validate_timespan( $db, $topic, $_ ) } @{ $timespans };
}

sub validate_topic_data($$)
{
    my ( $db, $topic ) = @_;

    my $completed = $MediaWords::AbstractJob::STATE_COMPLETED;

    is( $topic->{ state }, $completed, "twitter topic state" );

    my ( $failed_snapshots ) = $db->query( "select count(*) from snapshots where state <> ?", $completed )->flat;
    is( $failed_snapshots, 0, "number of failed snapshots" );

    my ( $num_matching_seed_urls ) = $db->query( <<SQL, $topic->{ topics_id } )->flat;
select count(*) from topic_tweet_full_urls where topics_id = \$1
SQL

    my ( $expected_num_urls ) = $db->query( "select count(*) from topic_tweet_urls" )->flat;
    is( $num_matching_seed_urls, $expected_num_urls, "seed urls match topic tweet urls" );

    my ( $num_dead_tweets ) = $db->query( <<SQL, $topic->{ topics_id } )->flat;
select count(*)
    from topic_dead_links tdl
        join topic_tweet_full_urls ttfu on
            ( ttfu.topics_id = tdl.topics_id and tdl.url = ttfu.url )
    where
        tdl.topics_id = \$1
SQL

    my ( $num_null_story_seed_urls ) = $db->query( <<SQL, $topic->{ topics_id } )->flat;
select count(*) from topic_seed_urls where stories_id is null and topics_id = \$1
SQL
    ok( $num_null_story_seed_urls <= $num_dead_tweets,
        "number of topic_seed_urls with null stories_id: $num_null_story_seed_urls <= $num_dead_tweets" );

    my ( $num_matching_topic_stories ) = $db->query( <<SQL, $topic->{ topics_id } )->flat;
select count(*) from topic_tweet_full_urls where stories_id is not null and topics_id = \$1
SQL

    my $num_processed_stories = $num_matching_topic_stories + $num_dead_tweets;

    is( $num_processed_stories, $expected_num_urls, "number of processed urls in twitter topic" );

    my ( $num_twitter_topic_stories ) = $db->query( <<SQL, $topic->{ topics_id } )->flat;
select count(*) from topic_stories where topics_id = ?
SQL

    validate_timespans( $db, $topic );
}

# core testing functionality
sub test_fetch_topic_tweets($)
{
    my ( $db ) = @_;

    # seed random number generator so that we get consistent results
    srand( 123456 );

    my $topic = MediaWords::Test::DB::create_test_topic( $db, 'tweet topic' );

    $topic->{ ch_monitor_id } = $CH_MONITOR_ID;
    $db->update_by_id( 'topics', $topic->{ topics_id }, $topic );

    my ( $start_date, $end_date ) = get_test_date_range();

    $db->query( <<SQL, $topic->{ topics_id }, $start_date, $end_date );
update topics set start_date = \$2, end_date = \$3 where topics_id = \$1
SQL

    # topic date modeling confuses perl TAP for some reason
    my $config     = MediaWords::Util::Config::get_config();
    my $new_config = python_deep_copy( $config );
    $new_config->{ mediawords }->{ topic_model_reps } = 0;
    MediaWords::Util::Config::set_config( $new_config );

    MediaWords::Job::TM::MineTopic->run_locally( { topics_id => $topic->{ topics_id }, test_mode => 1 } );

    $topic = $db->require_by_id( 'topics', $topic->{ topics_id } );

    my $test_dates = get_test_dates();
    for my $date ( @{ $test_dates } )
    {
        my $topic_tweet_day = $db->query( <<SQL, $topic->{ topics_id }, $date )->hash;
select * from topic_tweet_days where topics_id = \$1 and day = \$2
SQL
        ok( $topic_tweet_day, "topic_tweet_day created for $date" );
    }

    my ( $expected_num_ch_tweets ) = $db->query( "select sum( num_ch_tweets ) from topic_tweet_days" )->flat;
    my ( $num_tweets_inserted )    = $db->query( "select count(*) from topic_tweets" )->flat;
    is( $num_tweets_inserted, $expected_num_ch_tweets, "num of topic_tweets inserted" );
    ok( $num_tweets_inserted > 0, "num topic_tweets > 0" );

    my ( $num_null_text_tweets ) = $db->query( "select count(*) from topic_tweets where content is null" )->flat;
    is( $num_null_text_tweets, 0, "number of null text tweets" );

    my ( $num_null_date_tweets ) = $db->query( "select count(*) from topic_tweets where publish_date is null" )->flat;
    is( $num_null_date_tweets, 0, "number of null publish_date tweets" );

    my ( $num_short_tweets ) = $db->query( "select count(*) from topic_tweets where length( content ) < 16" )->flat;
    is( $num_short_tweets, 0, "number of short tweets" );

    my ( $num_short_users ) = $db->query( "select count(*) from topic_tweets where length( twitter_user ) < 3" )->flat;
    is( $num_short_users, 0, "number of short users" );

    validate_topic_tweet_urls( $db, $topic );
    validate_topic_data( $db, $topic );
}

# if the twitter and ch keys are setup, run the tests on the external apis
sub run_tests_on_external_apis
{
    my $config = MediaWords::Util::Config::get_config();

    if ( !$config->{ twitter }->{ consumer_secret } || !$config->{ crimson_hexagon }->{ key } )
    {
        WARN( "SKIPPING EXTERNAL APIS BECAUSE TWITTER AND/OR CRIMSON HEXAGON KEYS NOT FOUND" );
        ok( 1, "skipped test" );
    }
    else
    {
        MediaWords::Test::Supervisor::test_with_supervisor( \&test_fetch_topic_tweets, [ 'job_broker:rabbitmq' ] );
    }

    done_testing();
}

sub run_tests_on_mock_apis
{
    my $hs = MediaWords::Test::HTTP::HashServer->new(
        $PORT,
        {
            '/api/monitor/posts'    => { callback => \&mock_ch_posts },
            '/statuses/lookup.json' => { callback => \&mock_twitter_lookup },
            '/tweet_url'            => { callback => \&mock_tweet_url }
        }
    );
    $hs->start();

    MediaWords::Job::FetchTopicTweets->set_api_host( "http://localhost:$PORT" );
    my $config = MediaWords::Util::Config::get_config();

    # set dummy values so that we can hit the mock apis without the underlying modules complaining
    my $new_config = python_deep_copy( $config );
    $new_config->{ crimson_hexagon }->{ key } = 'TEST';
    map { $new_config->{ twitter }->{ $_ } = 'TEST' } qw/consumer_key consumer_secret access_token access_token_secret/;
    MediaWords::Util::Config::set_config( $new_config );

    eval { MediaWords::Test::Supervisor::test_with_supervisor( \&test_fetch_topic_tweets, [ 'job_broker:rabbitmq' ] ); };
    my $test_error = $@;

    $hs->stop();

    die( $test_error ) if ( $test_error );

    done_testing();
}

1;
