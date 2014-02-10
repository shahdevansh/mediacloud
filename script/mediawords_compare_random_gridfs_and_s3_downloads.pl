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
#   # Will compare 1000 randomly selected downloads in the interval between
#   # ~30 days old and ~1 day old
#   ./script/mediawords_compare_random_gridfs_and_s3_downloads.pl
#
# or
#
#   # Will compare 100 randomly selected downloads in the interval between
#   # ~7 days old and ~1 day old
#   ./script/mediawords_compare_random_gridfs_and_s3_downloads.pl \
#       --number_of_downloads_to_compare=100 \
#       --lower_interval="7 days" \
#       --upper_interval="1 day"
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::DBI::Downloads::Store::GridFS;
use MediaWords::DBI::Downloads::Store::AmazonS3;
use Getopt::Long;
use Text::Diff;
use Data::Dumper;

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

# Select and return a download ID on the specified interval
# Params: database object, interval
# Returns: download ID (up to 1 day older than the given interval)
# Dies on error
sub _downloads_id_for_interval($$)
{
    my ( $db, $interval ) = @_;

    # quote() will add single quotes ('')
    $interval = $db->dbh->quote( $interval );

    my ( $downloads_id ) = $db->query(
        <<"EOF"
            SELECT downloads_id AS max_downloads_id
            FROM downloads
            WHERE download_time > NOW() - INTERVAL $interval - INTERVAL '1 days'
              AND download_time < NOW() - INTERVAL $interval
            LIMIT 1
EOF
    )->flat;
    unless ( defined $downloads_id )
    {
        die "Unable to fetch download's ID for interval '$interval'.";
    }

    return $downloads_id;
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
sub compare_random_gridfs_and_s3_downloads($$$)
{
    my ( $number_of_downloads_to_compare, $lower_interval, $upper_interval ) = @_;

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
    my $min_downloads_id = _downloads_id_for_interval( $db, $lower_interval );
    my $max_downloads_id = _downloads_id_for_interval( $db, $upper_interval );

    say STDERR "Will fetch $number_of_downloads_to_compare random downloads up until download $max_downloads_id.";

    my $all_downloads_are_equal = 1;

    # Fetch a requested number of random downloads
    for ( my $x = 0 ; $x < $number_of_downloads_to_compare ; ++$x )
    {
        my $downloads_id = $db->query(
            <<EOF,
            SELECT get_random_gridfs_downloads_id(?, ?) AS random_downloads_id
EOF
            $min_downloads_id, $max_downloads_id
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
            say STDERR "\t\tGridFS download length: " . ( defined( $gridfs_content ) ? length( $gridfs_content ) : 'undef' );
            say STDERR "\t\tS3 download length: " .     ( defined( $s3_content )     ? length( $s3_content )     : 'undef' );
            if ( defined( $gridfs_content ) and defined( $s3_content ) )
            {
                my $diff = diff \$gridfs_content, \$s3_content, { STYLE => 'Unified' };
                say STDERR "\t\tDiff between GridFS (-) and S3 downloads:\n$diff";
            }

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
    my $number_of_downloads_to_compare = 1000;
    my $lower_interval                 = '30 days';
    my $upper_interval                 = '1 day';

    my Readonly $usage =
      'Usage: ' . $0 . ' [--number_of_downloads_to_compare=' . $number_of_downloads_to_compare .
      ']' . ' [--lower_interval="' . $lower_interval . '"]' . ' [--upper_interval="' . $upper_interval . '"]';

    GetOptions(
        'number_of_downloads_to_compare:i' => \$number_of_downloads_to_compare,
        'lower_interval:s'                 => \$lower_interval,
        'upper_interval:s'                 => \$upper_interval,
    ) or die "$usage\n";
    if ( $number_of_downloads_to_compare < 1 or ( !$lower_interval ) or ( !$upper_interval ) )
    {
        die "$usage";
    }

    say STDERR "starting --  " . localtime();
    say STDERR "Will compare $number_of_downloads_to_compare downloads";
    say STDERR "Approx. lower date bound: NOW() - INTERVAL '$lower_interval'";
    say STDERR "Approx. upper date bound: NOW() - INTERVAL '$upper_interval'";

    my $result = 0;    # fail by default
    eval {
        $result =
          compare_random_gridfs_and_s3_downloads( $number_of_downloads_to_compare, $lower_interval, $upper_interval );
    };
    if ( $@ )
    {
        die "The compare script died while comparing downloads: $@\n";
    }

    say STDERR "finished --  " . localtime();

    unless ( $result )
    {
        die "One or more downloads in GridFS and S3 are not equal.\n";
    }

    say STDERR "All $number_of_downloads_to_compare downloads are equal.";
}

main();
