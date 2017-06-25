use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use MediaWords::Test::HTTP::HashServer;
use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::Test::API;
use MediaWords::Test::DB;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

# test that a story has the expected content
sub _test_story_fields($$$)
{
    my ( $db, $story, $label ) = @_;

    my $expected_story = $db->require_by_id( 'stories', $story->{ stories_id } );

    my $fields = [ qw/stories_id url guid language publish_date media_id title collect_date/ ];
    map { is( $story->{ $_ }, $expected_story->{ $_ }, "$label field '$_'" ) } @{ $fields };
}

sub test_stories_corenlp($)
{
    my ( $db ) = @_;

    # TODO add infrastructure to actually generate CoreNLP and test it

    my $label = "stories/corenlp";

    # pick a stories_id that does not exist so that we make the end point just tell us that the
    # end point does not exist instead of triggering a fatal error
    my $stories_id = -1;

    my $r = test_get( '/api/v2/stories/corenlp', { stories_id => $stories_id } );

    is( scalar( @{ $r } ),         1,                      "$label num stories returned" );
    is( $r->[ 0 ]->{ stories_id }, $stories_id,            "$label stories_id" );
    is( $r->[ 0 ]->{ corenlp },    "story does not exist", "$label does not exist message" );
}

sub test_stories_fetch_bitly_clicks($)
{
    my ( $db ) = @_;

    # TODO add infrastructure to be able to test direct fetch from bitly

    # barring ability to test bitly fetch, just request a non-existent stories_id
    my $stories_id = -1;

    my $params = { stories_id => $stories_id, start_timestamp => '2016-01-01', end_timestamp => '2017-01-01' };
    my $r = test_get( '/api/v2/stories/fetch_bitly_clicks', $params, 1 );

    is( $r->{ error }, "stories_id '-1' does not exist" );
}

sub test_stories_list($)
{
    my ( $db ) = @_;

    my $label = "stories/list";

    my $stories = $db->query( <<SQL )->hashes;
select s.*,
        m.name media_name,
        m.url media_url,
        false ap_syndicated
    from stories s
        join media m using ( media_id )
    order by stories_id
    limit 10
SQL

    my $stories_ids_list = join( ' ', map { $_->{ stories_id } } @{ $stories } );

    my $params = {
        q                => "stories_id:( $stories_ids_list )",
        raw_1st_download => 1,
        sentences        => 1,
        text             => 1,
        corenlp          => 0
    };

    my $got_stories = test_get( '/api/v2/stories/list', $params );

    my $fields = [ qw/title description publish_date language collect_date ap_syndicated media_id media_name media_url/ ];
    rows_match( $label, $got_stories, $stories, 'stories_id', $fields );

    my $got_stories_lookup = {};
    map { $got_stories_lookup->{ $_->{ stories_id } } = $_ } @{ $got_stories };

    for my $story ( @{ $stories } )
    {
        my $sid       = $story->{ stories_id };
        my $got_story = $got_stories_lookup->{ $story->{ stories_id } };

        my $sentences = $db->query( "select * from story_sentences where stories_id = ?", $sid )->hashes;
        my $download_text = $db->query( <<SQL, $sid )->hash;
select dt.*
    from download_texts dt
        join downloads d using ( downloads_id )
    where d.stories_id = ?
    order by dt.download_texts_id
    limit 1
SQL
        my $content_ref = MediaWords::DBI::Stories::get_content_for_first_download( $db, $story );

        my $ss_fields = [ qw/is_dup language media_id publish_date sentence sentence_number story_sentences_id/ ];
        rows_match( "$label $sid sentences", $got_story->{ story_sentences }, $sentences, 'story_sentences_id', $ss_fields );

        is( $got_story->{ raw_first_download_file }, $$content_ref, "$label $sid download" );
        is( $got_story->{ story_text }, $download_text->{ download_text }, "$label $sid download_text" );
    }

    my $story = $stories->[ 0 ];

    my $got_story = test_get( '/api/v2/stories/single/' . $story->{ stories_id }, {} );
    rows_match( "stories/single", $got_story, [ $story ], 'stories_id', [ qw/stories_id title publish_date/ ] );
}

# various tests to validate stories_public/list
sub test_stories_public_list($$)
{
    my ( $db, $test_media ) = @_;

    my $stories = test_get( '/api/v2/stories_public/list', { q => 'title:story*', rows => 100000 } );

    my $expected_num_stories = $NUM_MEDIA * $NUM_FEEDS_PER_MEDIUM * $NUM_STORIES_PER_FEED;
    my $got_num_stories      = scalar( @{ $stories } );
    is( $got_num_stories, $expected_num_stories, "stories_public/list: number of stories" );

    my $title_stories_lookup = {};
    my $expected_stories = [ grep { $_->{ stories_id } } values( %{ $test_media } ) ];
    map { $title_stories_lookup->{ $_->{ title } } = $_ } @{ $expected_stories };

    for my $i ( 0 .. $expected_num_stories - 1 )
    {
        my $expected_title = "story story_$i";
        my $found_story    = $title_stories_lookup->{ $expected_title };
        ok( $found_story, "found story with title '$expected_title'" );
        _test_story_fields( $db, $stories->[ $i ], "all stories: story $i" );
    }

    my $search_result =
      test_get( '/api/v2/stories_public/list', { q => 'stories_id:' . $stories->[ 0 ]->{ stories_id } } );
    is( scalar( @{ $search_result } ), 1, "stories_public search: count" );
    is( $search_result->[ 0 ]->{ stories_id }, $stories->[ 0 ]->{ stories_id }, "stories_public search: stories_id match" );
    _test_story_fields( $db, $search_result->[ 0 ], "story_public search" );

    my $stories_single = test_get( '/api/v2/stories_public/single/' . $stories->[ 1 ]->{ stories_id } );
    is( scalar( @{ $stories_single } ), 1, "stories_public/single: count" );
    is( $stories_single->[ 0 ]->{ stories_id }, $stories->[ 1 ]->{ stories_id }, "stories_public/single: stories_id match" );
    _test_story_fields( $db, $search_result->[ 0 ], "stories_public/single" );

    # test feeds_id= param

    # expect error when including q= and feeds_id=
    test_get( '/api/v2/stories_public/list', { q => 'foo', feeds_id => 1 }, 1 );

    my $feed =
      $db->query( "select * from feeds where feeds_id in ( select feeds_id from feeds_stories_map ) limit 1" )->hash;
    my $feed_stories =
      test_get( '/api/v2/stories_public/list', { rows => 100000, feeds_id => $feed->{ feeds_id }, show_feeds => 1 } );
    my $expected_feed_stories = $db->query( <<SQL, $feed->{ feeds_id } )->hashes;
select s.* from stories s join feeds_stories_map fsm using ( stories_id ) where feeds_id = ?
SQL

    is( scalar( @{ $feed_stories } ), scalar( @{ $expected_feed_stories } ), "stories feed count feed $feed->{ feeds_id }" );
    for my $feed_story ( @{ $feed_stories } )
    {
        my ( $expected_story ) = grep { $_->{ stories_id } eq $feed_story->{ stories_id } } @{ $expected_feed_stories };
        ok( $expected_story,
            "stories feed story $feed_story->{ stories_id } feed $feed->{ feeds_id } matches expected story" );
        is( scalar( @{ $feed_story->{ feeds } } ), 1, "stories feed one feed returned" );
        for my $field ( qw/name url feeds_id media_id feed_type/ )
        {
            is( $feed_story->{ feeds }->[ 0 ]->{ $field }, $feed->{ $field }, "feed story field $field" );
        }
    }
}

sub test_stories_single($)
{
    my ( $db ) = @_;

    my $label = "stories/list";

    my $story = $db->query( <<SQL )->hash;
select s.*,
        m.name media_name,
        m.url media_url,
        false ap_syndicated
    from stories s
        join media m using ( media_id )
    order by stories_id
    limit 1
SQL

    my $got_stories = test_get( '/api/v2/stories/list', { q => "stories_id:$story->{ stories_id }" } );

    my $fields = [ qw/title description publish_date language collect_date ap_syndicated media_id media_name media_url/ ];
    rows_match( $label, $got_stories, [ $story ], 'stories_id', $fields );
}

sub test_stories_count($)
{
    my ( $db ) = @_;

    my $stories = $db->query( "select * from stories order by stories_id asc limit 23" )->hashes;

    my $stories_ids_list = join( ' ', map { $_->{ stories_id } } @{ $stories } );

    my $r = test_get( '/api/v2/stories/count', { q => "stories_id:($stories_ids_list)" } );

    is( $r->{ count }, scalar( @{ $stories } ), "stories/count count" );

    $r = test_get( '/api/v2/stories_public/count', { q => "stories_id:($stories_ids_list)" } );

    is( $r->{ count }, scalar( @{ $stories } ), "stories/count count" );
}

sub test_stories_word_matrix($)
{
    my ( $db ) = @_;

    my $label = "stories/word_matrix";

    my $stories          = $db->query( "select * from stories order by stories_id limit 17" )->hashes;
    my $stories_ids      = [ map { $_->{ stories_id } } @{ $stories } ];
    my $stories_ids_list = join( ' ', @{ $stories_ids } );

    # this functionality is already tested in test_get_story_word_matrix(), so we're just makingn sure no errors
    # are generated and the return format is correct

    my $r = test_get( '/api/v2/stories/word_matrix', { q => "stories_id:( $stories_ids_list )" } );
    ok( $r->{ word_matrix }, "$label word matrix present" );
    ok( $r->{ word_list },   "$label word list present" );

    $r = test_get( '/api/v2/stories_public/word_matrix', { q => "stories_id:( $stories_ids_list )" } );
    ok( $r->{ word_matrix }, "$label word matrix present" );
    ok( $r->{ word_list },   "$label word list present" );
}

sub test_stories($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    MediaWords::Test::DB::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    test_stories_corenlp( $db );
    test_stories_fetch_bitly_clicks( $db );
    test_stories_list( $db );
    test_stories_single( $db );
    test_stories_public_list( $db, $media );
    test_stories_count( $db );
    test_stories_word_matrix( $db );
}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_stories,
        [ 'solr_standalone', 'job_broker:rabbitmq', 'rescrape_media' ] );

    done_testing();
}

main();
