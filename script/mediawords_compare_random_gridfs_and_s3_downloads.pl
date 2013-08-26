#!/usr/bin/env perl
#
# Compare a variable number of random downloads from MongoDB GridFS to their
# (backed up) counterparts in Amazon S3.
#
# Treat Tar (path LIKE 'tar:%'), filesystem and GridFS (path LIKE 'gridfs:%')
# as being located in GridFS.
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

# Returns true if the downloads table contains at least one download that
# is stored to GridFS and is expected to be backed up to S3 (and thus the
# script can proceed).
# Used to prevent the fancy get_random_gridfs_downloads_id() PostgreSQL
# function (defined in script/mediawords.sql) from getting into an infinite
# loop.
# Params: database object
# Returns: true if there exists at least one download that is expected to
# be stored in GridFS and backed up to S3
sub _downloads_table_contains_gridfs_downloads($)
{
    my ( $db ) = @_;

    my $at_least_one_gridfs_download = $db->query(
        <<EOF
            SELECT 1
            FROM downloads
            WHERE state = 'success'
              AND file_status != 'missing'
              AND path NOT LIKE 'content:%'
              AND path != ''  -- some paths are empty
        LIMIT 1
EOF
    )->flat;
    if ( $at_least_one_gridfs_download )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Average table row count
# Params: database object, table name
# Returns: average table row count
sub _avg_table_row_count($$)
{
    my ( $db, $table_name ) = @_;

    my $downloads_avg_row_count = $db->query(
        <<EOF
        SELECT reltuples AS avg_row_count
        FROM pg_class
        WHERE oid = 'public.$table_name'::regclass
EOF
    )->flat;
    return $downloads_avg_row_count;
}

# Max. download's ID that is expected to be backed up to S3
# Params: database object,
# Returns: max. download's ID
# Dies on error
sub _max_downloads_id($$)
{
    my ( $db, $choose_from_downloads_order_than_day_before_yesterday ) = @_;

    my $sql = '';
    if ( $choose_from_downloads_order_than_day_before_yesterday )
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
    unless ( defined $max_downloads_id )
    {
        die "Unable to fetch max. downloads ID.";
    }

    return $max_downloads_id;
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

    # Ensure that there are downloads to choose from
    unless ( _downloads_table_contains_gridfs_downloads( $db ) )
    {
        die "There are no GridFS downloads in the downloads table.";
    }
    if ( _avg_table_row_count( $db, 'downloads' ) < $number_of_downloads_to_compare )
    {
        die "Downloads table is empty or has less rows than $number_of_downloads_to_compare.";
    }

    # Select the biggest download ID that might be available in S3
    my $max_downloads_id = _max_downloads_id( $db, CHOOSE_FROM_DOWNLOADS_ORDER_THAN_DAY_BEFORE_YESTERDAY );

    say STDERR "Will fetch $number_of_downloads_to_compare random downloads up until download $max_downloads_id.";

    my $all_downloads_are_equal = 1;

    # Fetch a requested number of random downloads
    for ( my $x = 0 ; $x < $number_of_downloads_to_compare ; ++$x )
    {
        my $downloads_id = $db->query(
            <<EOF,
            SELECT get_random_gridfs_downloads_id(?) AS random_downloads_id
EOF
            $max_downloads_id
        )->hash;
        unless ( $downloads_id and $downloads_id->{ random_downloads_id } )
        {
            die "Unable to fetch random download ID.";
        }
        $downloads_id = $downloads_id->{ random_downloads_id };

        # Compare
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
            # It is expected that the download will always exist in GridFS and thus in S3
            $downloads_are_equal = 0;
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

    say STDERR "finished --  " . localtime();

    if ( $result )
    {
        say STDERR "All $number_of_downloads_to_compare downloads are equal.";
    }
    else
    {
        die "One or more downloads in GridFS and S3 are not equal.\n";
    }
}

main();
