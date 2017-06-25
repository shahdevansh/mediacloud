use strict;
use warnings;

use Test::More tests => 183;

use English '-no_match_vars';
use List::Util;

use MediaWords::Util::Web::Cache;

BEGIN
{
    use_ok( 'MediaWords::Test::HTTP::HashServer' );
    use_ok( 'MediaWords::Util::Web::Cache' );
}

my $_port = 8899;

sub main
{

    my $pages = {};
    for my $i ( 1 .. 10 )
    {
        $pages->{ "/page-$i" }         = { page_num => $i, content  => "page-$i content" };
        $pages->{ "/redirect-$i" }     = { page_num => $i, redirect => "page-$i" };
        $pages->{ "/127-redirect-$i" } = { page_num => $i, redirect => "http://localhost:$_port/page-$i" };
    }

    my $hs = MediaWords::Test::HTTP::HashServer->new( $_port, $pages );

    ok( $hs, 'hashserver object returned' );

    $hs->start();

    my $urls;
    while ( my ( $path, $page ) = each( %{ $pages } ) )
    {
        my $expected_content = "page-$page->{ page_num } content";

        # do localhost twice to make sure cached link downloads work with duplicate urls
        push( @{ $urls }, { url => "http://localhost:$_port$path", page => $page, content => $expected_content } );
        push( @{ $urls }, { url => "http://localhost:$_port$path", page => $page, content => $expected_content } );
        push( @{ $urls }, { url => "http://127.0.0.1:$_port$path", page => $page, content => $expected_content } );
    }

    $urls = [ List::Util::shuffle( @{ $urls } ) ];

    MediaWords::Util::Web::Cache::cache_link_downloads( $urls );

    for my $url ( @{ $urls } )
    {
        my $content = MediaWords::Util::Web::Cache::get_cached_link_download( $url );
        chomp( $content );
        is( $content, $url->{ content }, "$url->{ url } content matches" );
        is( $url->{ _cached_link_downloads }, 1, "$url->{ url } downloaded exactly once" );
    }

    $hs->stop();
}

main();
