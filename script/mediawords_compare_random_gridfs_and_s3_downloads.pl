#!/usr/bin/env perl
#
# Compare a variable number of random downloads from MongoDB GridFS to their
# (backed up) counterparts in Amazon S3
#
# Exits with 0 when the downloads are equal, non-zero value when they're not
#
# Usage:
#
#   # Will compare 1000 random downloads
#   ./script/mediawords_compare_random_gridfs_and_s3_downloads.pl
#
# or
#
#   ./script/mediawords_compare_random_gridfs_and_s3_downloads.pl \
#       [--number_of_downloads_to_compare=count]
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;
use MediaWords::DBI::Downloads::Store::GridFS;
use MediaWords::DBI::Downloads::Store::AmazonS3;
use Getopt::Long;
use Data::Dumper;

# Default number of randomly chosen downloads to compare
use constant DEFAULT_NUMBER_OF_DOWNLOADS_TO_COMPARE => 1000;

# Should the script select only from downloads fetched no later than day before yesterday
# (useful if you're backing up downloads to S3 at midnight)
use constant CHOOSE_FROM_DOWNLOADS_ORDER_THAN_DAY_BEFORE_YESTERDAY => 1;

# Get a number of random download IDs from the database
# * due to the nature of implementation, download IDs might not be always unique
# * skips "content:" downloads
# Params: number of random download IDs to fetch
# Returns: arrayref of integer download IDs or empty arrayref
sub _get_random_download_ids($$)
{
    my ( $db, $num_random_downloads ) = @_;

    # Ensure that there are downloads to choose from
    my $downloads_avg_row_count = $db->query(
        <<EOF
        SELECT reltuples AS avg_row_count
        FROM pg_class
        WHERE oid = 'public.downloads'::regclass
EOF
    )->flat;
    if ( $downloads_avg_row_count < $num_random_downloads )
    {
        say STDERR "Downloads table is empty or has less rows than $num_random_downloads.";
        return [];
    }

    # Select the biggest download ID that might be available in S3
    my $sql = '';
    if ( CHOOSE_FROM_DOWNLOADS_ORDER_THAN_DAY_BEFORE_YESTERDAY )
    {
        $sql = <<EOF;
            SELECT downloads_id AS max_downloads_id
            FROM downloads
            WHERE download_time > DATE_TRUNC('day', NOW()) - INTERVAL '2 days'
              AND download_time < DATE_TRUNC('day', NOW()) - INTERVAL '1 day'
            LIMIT 1
EOF
    }
    else
    {
        $sql = <<EOF;
        SELECT MAX(downloads_id) AS max_downloads_id
        FROM downloads
EOF
    }
    my ( $max_downloads_id ) = $db->query( $sql )->flat;
    unless ( $max_downloads_id )
    {
        say STDERR "Unable to fetch the max. downloads ID.";
        return [];
    }

    say STDERR "Will fetch $num_random_downloads random downloads up until download $max_downloads_id.";

    # Fetch a requested number of random downloads
    my $download_ids = [];
    for ( my $x = 0 ; $x < $num_random_downloads ; ++$x )
    {

        my $random_downloads_id_offset = int( $max_downloads_id * rand() );

        my $random_download_id = $db->query(
            <<EOF,
            SELECT downloads_id
            FROM downloads
            WHERE state = 'success'
              AND file_status != 'missing'
              AND path NOT LIKE 'content:%'
              AND downloads_id >= ?
            ORDER BY downloads_id
            LIMIT 1
EOF
            $random_downloads_id_offset
        )->hash;
        unless ( $random_download_id and $random_download_id->{ downloads_id } )
        {
            say STDERR "Unable to fetch random download with offset $random_downloads_id_offset.";
            return [];
        }
        $random_download_id = $random_download_id->{ downloads_id };

        # say STDERR "Randomly chose download ID " . Dumper($random_download_id);
        push( @{ $download_ids }, $random_download_id );
    }

    # Sanity check
    if ( scalar( @{ $download_ids } ) != $num_random_downloads )
    {
        die "Unable to fetch $num_random_downloads (fetched only " . scalar( @{ $download_ids } ) . ")";
    }

    return $download_ids;
}

# Fetch download from the designated store, print verbose messages along the way
# Returns: download's contents or undef (if unable to fetch the download)
# Dies on error
sub _fetch_download($$)
{
    my ( $download_store, $downloads_id ) = @_;

    my $download = { downloads_id => $downloads_id };

    my $content_ref = undef;
    eval { $content_ref = $download_store->fetch_content( $download ); };
    if ( $@ )
    {
        say STDERR "\tUnable to fetch download $downloads_id from " . ref( $download_store ) . ": $@";
        $content_ref = undef;
    }
    else
    {
        if ( defined $content_ref )
        {
            say STDERR "\tDownload's $downloads_id length as fetched from " .
              ref( $download_store ) . ": " .
              length( $$content_ref );
        }
        else
        {
            say STDERR "\tDownload's $downloads_id as fetched from " . ref( $download_store ) . " is undefined.";
        }
    }

    if ( defined $content_ref )
    {
        return $$content_ref;
    }
    else
    {
        return undef;
    }
}

# Compares a number of GridFS downloads to their counterparts in S3
# Returns true if all the downloads are equal
# Returns false and prints out a warning to STDERR if one or more of downloads are not equal
# Dies on error
sub compare_random_gridfs_and_s3_downloads($)
{
    my ( $number_of_downloads_to_compare ) = @_;

    my $db           = MediaWords::DB::connect_to_db                      or die "Unable to connect to PostgreSQL.";
    my $gridfs_store = MediaWords::DBI::Downloads::Store::GridFS->new()   or die "Unable to connect to GridFS.";
    my $s3_store     = MediaWords::DBI::Downloads::Store::AmazonS3->new() or die "Unable to connect to Amazon S3.";

    say STDERR "Fetching $number_of_downloads_to_compare random download IDs...";
    my $random_download_ids = _get_random_download_ids( $db, $number_of_downloads_to_compare );
    unless ( scalar @{ $random_download_ids } )
    {
        die "Unable to fetch $number_of_downloads_to_compare random download IDs.";
    }

    my $all_downloads_are_equal = 1;

    foreach my $downloads_id ( @{ $random_download_ids } )
    {
        say STDERR "Testing download ID $downloads_id...";

        my $gridfs_content = _fetch_download( $gridfs_store, $downloads_id );
        my $s3_content     = _fetch_download( $s3_store,     $downloads_id );

        my $downloads_are_equal = 0;
        if ( defined( $gridfs_content ) and defined( $s3_content ) )
        {
            if ( $gridfs_content eq $s3_content )
            {

                # Both were successfully fetched and are equal
                $downloads_are_equal = 1;
            }
        }
        else
        {
            if ( ( !defined( $gridfs_content ) ) and ( !defined( $s3_content ) ) )
            {

                # Both are undef (considered equal)
                $downloads_are_equal = 1;
            }
        }

        unless ( $downloads_are_equal )
        {

            say STDERR "\tDownload ID $downloads_id mismatch:";
            say STDERR "\t\tDownload ID $downloads_id as fetched from GridFS: " .
              ( defined( $gridfs_content ) ? 'length = ' . length( $gridfs_content ) : 'undef' );
            say STDERR "\t\tDownload ID $downloads_id as fetched from S3: " .
              ( defined( $s3_content ) ? 'length = ' . length( $s3_content ) : 'undef' );

            $all_downloads_are_equal = 0;
        }
    }

    return $all_downloads_are_equal;
}

sub main
{
    binmode( STDOUT, ':utf8' );
    binmode( STDERR, ':utf8' );

    # (optional) number of downloads to compare
    my $number_of_downloads_to_compare = DEFAULT_NUMBER_OF_DOWNLOADS_TO_COMPARE;

    my Readonly $usage = 'Usage: ' . $0 . ' [--number_of_downloads_to_compare=count]';

    GetOptions( 'number_of_downloads_to_compare:i' => \$number_of_downloads_to_compare, ) or die "$usage\n";
    if ( $number_of_downloads_to_compare < 1 )
    {
        die "$usage";
    }

    say STDERR "starting --  " . localtime();
    say STDERR "Will compare $number_of_downloads_to_compare downloads";

    my $result = 0;    # fail by default
    eval { $result = compare_random_gridfs_and_s3_downloads( $number_of_downloads_to_compare ); };
    if ( $@ )
    {
        die "The compare script died while comparing downloads: $@\n";
    }
    unless ( $result )
    {
        die "One or more downloads in GridFS and S3 are not equal.\n";
    }

    say STDERR "All $number_of_downloads_to_compare downloads are equal.";
    say STDERR "finished --  " . localtime();
}

main();
