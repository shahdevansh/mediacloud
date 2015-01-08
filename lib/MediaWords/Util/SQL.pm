package MediaWords::Util::SQL;

# misc utility functions for sql

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use DateTime;
use Time::Local;
use Carp;

my $_local_tz = DateTime::TimeZone->new( name => 'local' );

# given a ref to a list of ids, return a list suitable
# for including in a query as an in list, eg:
# 1,2,3,4
sub get_ids_in_list
{
    my ( $list ) = @_;

    if ( grep( /[^0-9]/, @{ $list } ) )
    {
        confess "non-number list id list: " . join( ', ', @{ $list } );
    }

    return join( ',', @{ $list } );
}

sub get_sql_date_from_epoch
{
    my ( $epoch ) = @_;

    my $dt = DateTime->from_epoch( epoch => $epoch );
    $dt->set_time_zone( $_local_tz );

    return $dt->datetime;
}

# Given one of the SQL date formats, either:
# * "YYYY-MM-DD" or
# * "YYYY-MM-DD HH:mm:ss", or
# * "YYYY-MM-DD HH:mm:ss.ms"
# return the epoch time (UNIX timestamp)
sub get_epoch_from_sql_date($)
{
    my $date = shift;

    unless ( $date )
    {
        confess "Date is undefined or empty.";
    }

    unless ( $date =~ /^\d\d\d\d-\d\d-\d\d$/
        or $date =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$/
        or $date =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\.\d{1,6}$/ )
    {
        confess "Date is invalid: $date";
    }

    my $year  = substr( $date, 0, 4 );
    my $month = substr( $date, 5, 2 );
    my $day   = substr( $date, 8, 2 );

    return Time::Local::timelocal( 0, 0, 0, $day, $month - 1, $year );
}

# given a date in the sql format 'YYYY-MM-DD', increment it by $days days
sub increment_day
{
    my ( $date, $days ) = @_;

    return $date if ( defined( $days ) && ( $days == 0 ) );

    $days = 1 if ( !defined( $days ) );

    my $epoch_date = get_epoch_from_sql_date( $date ) + ( ( ( $days * 24 ) + 12 ) * 60 * 60 );

    my ( undef, undef, undef, $day, $month, $year ) = localtime( $epoch_date );

    return sprintf( '%04d-%02d-%02d', $year + 1900, $month + 1, $day );
}

# decrease the given date to the latest monday equal to or before the date
sub truncate_to_monday($)
{
    my ( $date ) = @_;

    my $epoch_date = get_epoch_from_sql_date( $date );
    my $week_day   = ( localtime( $epoch_date ) )[ 6 ];

    # mod this to account for sunday, for which $week_day - 1 == -1
    my $days_offset = ( $week_day - 1 ) % 7;

    return increment_day( $date, -1 * $days_offset );
}

# decrease the given date to the first day of the current month
sub truncate_to_start_of_month($)
{
    my ( $date ) = @_;

    my $epoch_date = get_epoch_from_sql_date( $date );
    my $month_day  = ( localtime( $epoch_date ) )[ 3 ];

    my $days_offset = $month_day - 1;

    return increment_day( $date, -1 * $days_offset );
}

1;
