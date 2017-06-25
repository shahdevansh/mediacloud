#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin";
    use lib "$FindBin::Bin/../lib";
    use Catalyst::Test 'MediaWords';
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use List::MoreUtils "uniq";
use List::Util "shuffle";
use Math::Prime::Util;
use Readonly;
use Test::More;

use MediaWords;
use MediaWords::TM::Snapshot;
use MediaWords::DB::Schema;
use MediaWords::DBI::Auth::Roles;
use MediaWords::Test::API;
use MediaWords::Test::DB;
use MediaWords::Test::Supervisor;
use MediaWords::Util::Web;
use MediaWords::Util::Config;

Readonly my $TEST_HTTP_SERVER_PORT => '3000';

Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;

# This should match the DEFAULT_STORY_LIMIT in Stories.pm
Readonly my $DEFAULT_STORY_LIMIT => 20;

# A constant used to generate consistent orderings in test sorts
Readonly my $TEST_MODULO => 6;

sub add_topic_link
{
    my ( $db, $topic, $story, $ref_story ) = @_;

    $db->create(
        'topic_links',
        {
            topics_id      => $topic->{ topics_id },
            stories_id     => $story,
            url            => 'http://foo',
            redirect_url   => 'http://foo',
            ref_stories_id => $ref_story,
        }
    );

}

sub add_bitly_count
{
    my ( $db, $id, $story, $click_count ) = @_;
    $db->query( "insert into bitly_clicks_total values ( \$1,\$2,\$3 )", $id, $story->{ stories_id }, $click_count );
}

sub add_topic_story
{
    my ( $db, $topic, $story ) = @_;

    $db->create( 'topic_stories', { stories_id => $story->{ stories_id }, topics_id => $topic->{ topics_id } } );
}

sub create_stories
{
    my ( $db, $stories, $topics ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, $stories );
}

sub create_test_data
{

    my ( $test_db, $topic_media_sources ) = @_;

    my $NUM_LINKS_PER_PAGE = 10;

    srand( 3 );

    # populate topics table
    my $topic = $test_db->create(
        'topics',
        {
            name                => 'foo',
            solr_seed_query     => '',
            solr_seed_query_run => 'f',
            pattern             => '',
            description         => 'test topic',
            start_date          => '2014-04-01',
            end_date            => '2014-06-01',
            job_queue           => 'mc',
            max_stories         => 100_000
        }
    );

    # populate topics_stories table
    # only include stories with id not multiples of $TEST_MODULO
    my $all_stories   = {};
    my $topic_stories = [];

    for my $m ( values( %{ $topic_media_sources } ) )
    {
        for my $f ( values( %{ $m->{ feeds } } ) )
        {
            while ( my ( $num, $story ) = each( %{ $f->{ stories } } ) )
            {
                if ( $num % $TEST_MODULO )
                {
                    my $cs = add_topic_story( $test_db, $topic, $story );
                    push @{ $topic_stories }, $story->{ stories_id };
                }
                $all_stories->{ int( $num ) } = $story->{ stories_id };

                # modding by a different number than stories included in topics
                # so that we will have bitly counts of 0

                add_bitly_count( $test_db, $num, $story, $num % ( $TEST_MODULO - 1 ) );
            }
        }
    }

    # populate topics_links table
    while ( my ( $num, $story_id ) = each %{ $all_stories } )
    {
        my @factors = Math::Prime::Util::factor( $num );
        foreach my $factor ( uniq @factors )
        {
            if ( $factor != $num )
            {
                add_topic_link( $test_db, $topic, $all_stories->{ $factor }, $story_id );
            }
        }
    }

    MediaWords::Job::TM::SnapshotTopic->run_locally( { topics_id => $topic->{ topics_id } } );

}

sub test_media_list
{
    my ( $data ) = @_;

    my $actual_response = test_get( '/api/v2/topics/1/media/list' );

    ok( scalar @{ $actual_response->{ media } } == 3,
        "returned unexpected number of media scalar $actual_response->{ media }" );

    # Check descending link count
    foreach my $m ( 1 .. $#{ $actual_response->{ media } } )
    {
        ok( $actual_response->{ media }[ $m ]->{ inlink_count } <= $actual_response->{ media }[ $m - 1 ]->{ inlink_count } );
    }

    # Check that we have right number of inlink counts for each media source

    my $topic_stories = _get_story_link_counts( $data );

    my $inlink_counts = { F => 4, D => 2, A => 0 };

    foreach my $mediasource ( @{ $actual_response->{ media } } )
    {
        ok( $mediasource->{ inlink_count } == $inlink_counts->{ $mediasource->{ name } } );
    }
}

sub test_story_count
{

    # The number of stories returned in stories/list matches the count in timespan

    my $story_limit = 10;

    my $actual_response = test_get( '/api/v2/topics/1/stories/list', { limit => $story_limit } );

    is( scalar @{ $actual_response->{ stories } }, $story_limit, "story limit" );

}

sub _get_story_link_counts
{
    my $data = shift;

    # umber of prime factors outside the media source
    my $counts = {
        1  => 0,
        2  => 0,
        3  => 0,
        4  => 0,
        5  => 0,
        7  => 0,
        8  => 1,
        9  => 1,
        10 => 2,
        11 => 0,
        13 => 0,
        14 => 2,
        15 => 0
    };

    my %return_counts = map { "story " . $_ => $counts->{ $_ } } keys %{ $counts };
    return \%return_counts;

}

sub _get_expected_bitly_link_counts
{
    my $return_counts = {};

    foreach my $m ( 1 .. 15 )
    {
        if ( $m % $TEST_MODULO )
        {
            $return_counts->{ "story " . $m } = $m % ( $TEST_MODULO - 1 );
        }
    }

    return $return_counts;
}

sub test_default_sort
{

    my $data = shift;

    my $base_url = '/api/v2/topics/1/stories/list';

    my $sort_key = "inlink_count";

    my $expected_counts = _get_story_link_counts( $data );

    _test_sort( $data, $expected_counts, $base_url, $sort_key );

}

sub test_social_sort
{

    my $data = shift;

    my $base_url = '/api/v2/topics/1/stories/list';

    my $sort_key = "bitly_click_count";

    my $expected_counts = _get_expected_bitly_link_counts();

    _test_sort( $data, $expected_counts, $base_url, $sort_key );
}

sub _test_sort
{

    # Make sure that only expected stories are in stories list response
    # in the appropriate order

    my ( $data, $expected_counts, $base_url, $sort_key ) = @_;

    my $actual_response = test_get( $base_url, { limit => 20, sort => $sort_key } );

    my $actual_stories_inlink_counts = {};
    my $actual_stories_order         = ();

    foreach my $story ( @{ $actual_response->{ stories } } )
    {
        $actual_stories_inlink_counts->{ $story->{ 'title' } } = $story->{ $sort_key };
        my @story_info = ( $story->{ $sort_key }, $story->{ 'stories_id' } );
        push @{ $actual_stories_order }, \@story_info;
    }

    is_deeply( $actual_stories_inlink_counts, $expected_counts, 'expected stories' );
}

# test topics create and update
sub test_topics_crud($)
{
    my ( $db ) = @_;

    # verify required params
    test_post( '/api/v2/topics/create', {}, 1 );

    my $label = "create topic";

    MediaWords::Test::DB::create_test_story_stack_numerated( $db, 10, 2, 2, $label );
    $db->query( "insert into tag_sets ( name ) values ( 'create topic' )" );
    $db->query( "insert into tags ( tag, tag_sets_id ) select m.name, ts.tag_sets_id from media m, tag_sets ts" );

    my $media_ids = $db->query( "select media_id from media limit 5" )->flat;
    my $tags_ids  = $db->query( "select tags_id from tags limit 5" )->flat;

    my $input = {
        name            => "$label name ",
        description     => "$label description",
        solr_seed_query => "$label query",
        max_iterations  => 12,
        start_date      => '2016-01-01',
        end_date        => '2017-01-01',
        is_public       => 1,
        ch_monitor_id   => 123456,
        media_ids       => $media_ids,
        media_tags_ids  => $tags_ids
    };

    my $r = test_post( '/api/v2/topics/create', $input );

    ok( $r->{ topics }, "$label JSON includes topics" );
    my $got_topic = $r->{ topics }->[ 0 ];

    my $exists_in_db = $db->find_by_id( "topics", $got_topic->{ topics_id } );
    ok( $exists_in_db, "$label topic exists in db" );

    my $test_fields = [ qw/name description solr_seed_query max_ierations start_date end_date is_public ch_monitor_id/ ];
    map { is( $got_topic->{ $_ }, $input->{ $_ }, "$label $_" ) } @{ $test_fields };

    my $topics_id = $got_topic->{ topics_id };

    my $got_media_ids = [ map { $_->{ media_id } } @{ $got_topic->{ media } } ];
    is_deeply( [ sort @{ $media_ids } ], [ sort @{ $media_ids } ], "$label media ids" );

    my $got_tags_ids = [ map { $_->{ tags_id } } @{ $got_topic->{ media_tags } } ];
    is_deeply( [ sort @{ $got_tags_ids } ], [ sort @{ $tags_ids } ], "$label media tag ids" );

    is( $got_topic->{ job_queue }, 'mc', "$label queue for admin user" );

    my $update_media_ids = [ @{ $media_ids } ];
    pop( @{ $update_media_ids } );
    my $update_tags_ids = [ @{ $tags_ids } ];
    pop( @{ $update_tags_ids } );

    my $update = {
        name            => "$label name update",
        description     => "$label description update",
        solr_seed_query => "$label query update",
        max_iterations  => 22,
        start_date      => '2016-01-02',
        end_date        => '2017-01-02',
        is_public       => 0,
        ch_monitor_id   => 1234567,
        media_ids       => $update_media_ids,
        media_tags_ids  => $update_tags_ids
    };

    $label = 'update topic';

    $r = test_put( "/api/v2/topics/$topics_id/update", $update );

    ok( $r->{ topics }, "$label JSON includes topics" );
    $got_topic = $r->{ topics }->[ 0 ];

    map { is( $got_topic->{ $_ }, $update->{ $_ }, "$label $_" ) } @{ $test_fields };

    $got_media_ids = [ map { $_->{ media_id } } @{ $got_topic->{ media } } ];
    is_deeply( [ sort @{ $got_media_ids } ], [ sort @{ $update_media_ids } ], "$label media ids" );

    $got_tags_ids = [ map { $_->{ tags_id } } @{ $got_topic->{ media_tags } } ];
    is_deeply( [ sort @{ $got_tags_ids } ], [ sort @{ $update_tags_ids } ], "$label media tag ids" );
}

# test topics/spider call
sub test_topics_spider($)
{
    my ( $db ) = @_;

    my $topic = MediaWords::Test::DB::create_test_topic( $db, 'spider test' );

    $topic = $db->update_by_id( 'topics', $topic->{ topics_id }, { solr_seed_query => 'BOGUSQUERYTORETURNOSTORIES' } );
    my $topics_id = $topic->{ topics_id };

    my $r = test_post( "/api/v2/topics/$topics_id/spider", {} );

    ok( $r->{ job_state }, "spider return includes job_state" );

    is( $r->{ job_state }->{ state }, $MediaWords::AbstractJob::STATE_QUEUED, "spider state" );
    is( $r->{ job_state }->{ topics_id }, $topic->{ topics_id }, "spider topics_id" );

    $r = test_get( "/api/v2/topics/$topics_id/spider_status" );

    ok( $r->{ job_states }, "spider status return includes job_states" );

    is( $r->{ job_states }->[ 0 ]->{ state }, $MediaWords::AbstractJob::STATE_QUEUED, "spider_status state" );
    is( $r->{ job_states }->[ 0 ]->{ topics_id }, $topic->{ topics_id }, "spider_status topics_id" );
}

# test topics/list
sub test_topics_list($)
{
    my ( $db ) = @_;

    my $label = "topics list";

    my $match_fields = [
        qw/name pattern solr_seed_query solr_seed_query_run description max_iterations start_date end_date state
          message job_queue max_stories/
    ];

    my $topic_private_a = MediaWords::Test::DB::create_test_topic( $db, "label private a" );
    my $topic_private_b = MediaWords::Test::DB::create_test_topic( $db, "label private b" );
    my $topic_public_a  = MediaWords::Test::DB::create_test_topic( $db, "label public a" );
    my $topic_public_b  = MediaWords::Test::DB::create_test_topic( $db, "label public b" );

    map { $db->update_by_id( 'topics', $_->{ topics_id }, { is_public => 't' } ) } ( $topic_public_a, $topic_public_b );

    {
        my $r = test_get( "/api/v2/topics/list", {} );
        my $expected_topics = $db->query( "select * from topics order by topics_id" )->hashes;
        ok( $r->{ topics }, "$label topics field present" );
        rows_match( $label, $r->{ topics }, $expected_topics, 'topics_id', $match_fields );
    }

    {
        $label = "$label with name";
        my $r = test_get( "/api/v2/topics/list", { name => 'label private a' } );
        my $expected_topics = $db->query( "select * from topics where name = 'label private a'" )->hashes;
        ok( $r->{ topics }, "$label topics field present" );
        rows_match( $label, $r->{ topics }, $expected_topics, 'topics_id', $match_fields );
    }

    {
        $label = "$label public";
        my $r = test_get( "/api/v2/topics/list", { public => 1 } );
        my $expected_topics = $db->query( "select * from topics where name % 'public ?'" )->hashes;
        ok( $r->{ topics }, "$label topics field present" );
        rows_match( $label, $r->{ topics }, $expected_topics, 'topics_id', $match_fields );
    }

    {
        $label = "$label list only permitted topics";
        my $api_key = MediaWords::Test::API::get_test_api_key();

        my $auth_user = $db->query(
            <<SQL,
            SELECT auth_users_id
            FROM auth_user_api_keys
            WHERE api_key = ?
SQL
            $api_key
        )->hash;
        my $auth_users_id = $auth_user->{ auth_users_id };

        $db->query( "delete from auth_users_roles_map where auth_users_id = ?", $auth_users_id );

        my $r               = test_get( "/api/v2/topics/list" );
        my $expected_topics = $db->query( "select * from topics where name % 'public ?'" )->hashes;
        ok( $r->{ topics }, "$label topics field present" );

        rows_match( $label, $r->{ topics }, $expected_topics, 'topics_id', $match_fields );

        $db->query( <<SQL, $auth_users_id, $MediaWords::DBI::Auth::Roles::List::ADMIN );
insert into auth_users_roles_map ( auth_users_id, auth_roles_id )
    select ?, auth_roles_id from auth_roles where role = ?
SQL
    }

}

# test topics/* calls
sub test_topics($)
{
    my ( $db ) = @_;

    test_topics_list( $db );
    test_topics_crud( $db );
    test_topics_spider( $db );
}

# test snapshots/generate and /generate_status
sub test_snapshots_generate($)
{
    my ( $db ) = @_;

    my $label = 'snapshot generate';

    my $topic = MediaWords::Test::DB::create_test_topic( $db, $label );

    $topic = $db->update_by_id( 'topics', $topic->{ topics_id }, { solr_seed_query => 'BOGUSQUERYTORETURNOSTORIES' } );
    my $topics_id = $topic->{ topics_id };

    my $r = test_post( "/api/v2/topics/$topics_id/snapshots/generate", {} );

    ok( $r->{ job_state }, "$label return includes job_state" );

    is( $r->{ job_state }->{ state }, $MediaWords::AbstractJob::STATE_QUEUED, "$label state" );
    is( $r->{ job_state }->{ topics_id }, $topic->{ topics_id }, "$label topics_id" );

    $r = test_get( "/api/v2/topics/$topics_id/snapshots/generate_status" );

    $label = 'snapshot generate_status';

    ok( $r->{ job_states }, "$label return includes job_states" );

    is( $r->{ job_states }->[ 0 ]->{ state }, $MediaWords::AbstractJob::STATE_QUEUED, "$label status state" );
    is( $r->{ job_states }->[ 0 ]->{ topics_id }, $topic->{ topics_id }, "$label topics_id" );
}

# test snapshots/* calls
sub test_snapshots($)
{
    my ( $db ) = @_;

    test_snapshots_generate( $db );
}

# test stories/facebook list
sub test_stories_facebook($)
{
    my ( $db ) = @_;

    my $label = "stories/facebook";

    my $topic   = $db->query( "select * from topics limit 1" )->hash;
    my $stories = $db->query( "select * from snap.live_stories limit 10" )->hashes;

    my $expected_ss = [];
    for my $story ( @{ $stories } )
    {
        my $stories_id = $story->{ stories_id };
        my $ss         = $db->create(
            'story_statistics',
            {
                stories_id                => $stories_id,
                facebook_share_count      => $stories_id + 1,
                facebook_comment_count    => $stories_id + 2,
                facebook_api_collect_date => $story->{ publish_date }
            }
        );

        push( @{ $expected_ss }, $ss );
    }

    my $r = test_get( "/api/v2/topics/$topic->{ topics_id }/stories/facebook", {} );

    my $got_ss = $r->{ counts };
    ok( $got_ss, "$label counts field present" );

    my $fields = [ qw/facebook_share_count facebook_comment_count facebook_api_collect_date/ ];
    rows_match( $label, $got_ss, $expected_ss, 'stories_id', $fields );
}

sub test_topics_api
{
    my $db = shift;

    my $stories = {
        A => {
            B => [ 1, 2, 3 ],
            C => [ 4, 5, 6, 15 ]
        },
        D => { E => [ 7, 8, 9 ] },
        F => {
            G => [ 10, ],
            H => [ 11, 12, 13, 14, ]
        }
    };

    MediaWords::Test::API::setup_test_api_key( $db );

    my $topic_media = create_stories( $db, $stories );

    create_test_data( $db, $topic_media );
    test_story_count();
    test_default_sort( $stories );
    test_social_sort( $stories );
    test_media_list( $stories );
    test_stories_facebook( $db );

    test_topics( $db );
    test_snapshots( $db );

}

sub main
{
    # topic date modeling confuses perl TAP for some reason
    MediaWords::Util::Config::get_config()->{ mediawords }->{ topic_model_reps } = 0;

    MediaWords::Test::Supervisor::test_with_supervisor( \&test_topics_api, [ 'solr_standalone', 'job_broker:rabbitmq' ] );

    done_testing();
}

main();
