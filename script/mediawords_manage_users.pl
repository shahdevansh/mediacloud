#!/usr/bin/env perl
#
# CLI user manager
#
#
# Usage
# =====
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl --help          # manager's help
#     or
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl --action=...    # action's help
#
# Add user
# --------
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
#         --action=add \
#         --email=jdoe@cyber.law.harvard.edu \
#         --full_name="John Doe" \
#         --notes="Media Cloud developer." \
#         --roles="query-create,media-edit,stories-edit" \
#         [--password="correct horse battery staple"] \
#         [--weekly_requests_limit=2000] \
#         [--weekly_requested_items_limit=10000]
#
#     Notes:
#     * Skip the `--password` parameter to read the password from STDIN.
#
# Modify user
# -----------
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
#         --action=modify \
#         --email=jdoe@cyber.law.harvard.edu \
#         [--full_name="John Doe"] \
#         [--notes="Media Cloud developer."] \
#         [--active|--inactive] \
#         [--roles="query-create,media-edit,stories-edit"] \
#         [--password="correct horse battery staple" | --set-password] \
#         [--weekly_requests_limit=2000] \
#         [--weekly_requested_items_limit=10000]
#
#     Notes:
#     * Pass only those parameters that you want to change; skip the ones that you want to leave inact.
#     * You can change the user's password either by:
#         * passing the new password as the value of `--password`, or
#         * proving the `--set-password` parameter to read the new password from STDIN.
#
# Delete user
# -----------
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
#         --action=delete \
#         --email=jdoe@cyber.law.harvard.edu
#
# Show user information
# ---------------------
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
#         --action=show \
#         --email=jdoe@cyber.law.harvard.edu
#
# List all users
# --------------
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
#         --action=list
#
# List all user roles
# -------------------
#
#     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
#         --action=roles
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Auth;
use MediaWords::Util::Config;

use Data::Dumper;
use Getopt::Long qw(:config pass_through);
use Term::Prompt;
use Term::ReadKey;

# Helper to read passwords from CLI without showing them
# (http://stackoverflow.com/a/701234/200603 plus http://search.cpan.org/dist/TermReadKey/ReadKey.pm)
sub _read_password
{
    # Start reading the keys
    my $password = '';

    ReadMode( 2 );    # cooked mode with echo off.

    # This will continue until the Enter key is pressed (decimal value of 10)
    while ( ord( my $key = ReadKey( 0 ) ) != 10 )
    {
        # For all value of ord($key) see http://www.asciitable.com/
        if ( ord( $key ) == 127 || ord( $key ) == 8 )
        {
            # Delete / Backspace was pressed
            # 1. Delete the last char from the password
            chop( $password );

            # 2. Move the cursor back by one, print a blank character, move the cursor back by one
            print "\b \b";
        }
        elsif ( ord( $key ) < 32 )
        {
            # Do nothing with control characters
        }
        else
        {
            $password .= $key;
        }
    }

    ReadMode( 0 );    # reset the terminal once we are done

    print "\n";

    return $password;
}

# Add user; returns 0 on success, 1 on error
sub user_add($)
{
    my ( $db ) = @_;

    my $user_email                        = undef;
    my $user_full_name                    = '';
    my $user_notes                        = '';
    my $user_roles                        = '';
    my $user_password                     = undef;
    my $user_weekly_requests_limit        = undef;
    my $user_weekly_requested_items_limit = undef;

    my Readonly $user_add_usage = <<"EOF";
Usage: $0 --action=add \
    --email=jdoe\@cyber.law.harvard.edu \
    --full_name="John Doe" \
    [--notes="Media Cloud developer."] \
    [--roles="query-create,media-edit,stories-edit"] \
    [--password="correct horse battery staple"] \
    [--weekly_requests_limit=2000] \
    [--weekly_requested_items_limit=10000]
EOF

    GetOptions(
        'email=s'                        => \$user_email,
        'full_name=s'                    => \$user_full_name,
        'notes:s'                        => \$user_notes,
        'roles:s'                        => \$user_roles,
        'password:s'                     => \$user_password,
        'weekly_requests_limit:i'        => \$user_weekly_requests_limit,
        'weekly_requested_items_limit:i' => \$user_weekly_requested_items_limit
    ) or die "$user_add_usage\n";
    die "$user_add_usage\n" unless ( $user_email and $user_full_name );

    # Roles array
    $user_roles = [ split( ',', $user_roles ) ];
    my $user_role_ids = [];
    foreach my $user_role ( @{ $user_roles } )
    {
        my $user_role_id;
        eval { $user_role_id = MediaWords::DBI::Auth::Roles::role_id_for_role( $db, $user_role ); };
        if ( $@ or ( !$user_role_id ) )
        {
            ERROR "Role '$user_role' was not found.";
            return 1;
        }

        push( @{ $user_role_ids }, $user_role_id );
    }

    if ( scalar @{ $user_role_ids } == 0 )
    {
        $user_role_ids = MediaWords::DBI::Auth::Roles::default_role_ids( $db );
    }

    $user_weekly_requests_limit        //= MediaWords::DBI::Auth::Limits::default_weekly_requests_limit( $db );
    $user_weekly_requested_items_limit //= MediaWords::DBI::Auth::Limits::default_weekly_requested_items_limit( $db );

    # Read password if not set
    my $user_password_repeat = undef;
    if ( $user_password )
    {
        $user_password_repeat = $user_password;
    }
    else
    {
        while ( !$user_password )
        {
            print "Enter password: ";
            $user_password = _read_password();
        }
        while ( !$user_password_repeat )
        {
            print "Repeat password: ";
            $user_password_repeat = _read_password();
        }
    }

    # Add the user
    eval {
        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email                        => $user_email,
            full_name                    => $user_full_name,
            notes                        => $user_notes,
            role_ids                     => $user_role_ids,
            active                       => 1,
            password                     => $user_password,
            password_repeat              => $user_password_repeat,
            activation_url               => '',                                   # user is active
            weekly_requests_limit        => $user_weekly_requests_limit,
            weekly_requested_items_limit => $user_weekly_requested_items_limit,
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    if ( $@ )
    {
        ERROR "Error while trying to add user: $@";
        return 1;
    }

    INFO "User with email address '$user_email' was successfully added.";

    return 0;
}

# Modify user; returns 0 on success, 1 on error
sub user_modify($)
{
    my ( $db ) = @_;

    my (
        $user_email,                          #
        $user_full_name,                      #
        $user_notes,                          #
        $user_is_active,                      #
        $user_is_inactive,                    #
        $user_roles,                          #
        $user_password,                       #
        $user_set_password,                   #
        $user_weekly_requests_limit,          #
        $user_weekly_requested_items_limit    #
    );

    my Readonly $user_modify_usage = <<"EOF";
Usage: $0 --action=modify \
    --email=jdoe\@cyber.law.harvard.edu \
    [--full_name="John Doe"] \
    [--notes="Media Cloud developer."] \
    [--active|--inactive] \
    [--roles="query-create,media-edit,stories-edit"] \
    [--password="correct horse battery staple" | --set-password] \
EOF

    GetOptions(
        'email=s'                        => \$user_email,
        'full_name:s'                    => \$user_full_name,
        'notes:s'                        => \$user_notes,
        'active'                         => \$user_is_active,
        'inactive'                       => \$user_is_inactive,
        'roles:s'                        => \$user_roles,
        'password:s'                     => \$user_password,
        'set-password'                   => \$user_set_password,
        'weekly_requests_limit:i'        => \$user_weekly_requests_limit,
        'weekly_requested_items_limit:i' => \$user_weekly_requested_items_limit
    ) or die "$user_modify_usage\n";
    die "$user_modify_usage\n" unless ( $user_email );

    my $user_role_ids = undef;
    if ( defined $user_roles )
    {

        my $roles = [ split( ',', $user_roles ) ];

        $user_role_ids = [];
        foreach my $user_role ( @{ $roles } )
        {
            my $user_role_id;
            eval { $user_role_id = MediaWords::DBI::Auth::Roles::role_id_for_role( $db, $user_role ); };
            if ( $@ or ( !$user_role_id ) )
            {
                ERROR "Role '$user_role' was not found.";
                return 1;
            }

            push( @{ $user_role_ids }, $user_role_id );
        }
    }

    if ( defined $user_is_inactive )
    {
        $user_is_active = 0;
    }

    my $user_password_repeat = $user_password;
    if ( $user_set_password )
    {
        while ( !$user_password )
        {
            print "Enter password: ";
            $user_password = _read_password();
        }
        while ( !$user_password_repeat )
        {
            print "Repeat password: ";
            $user_password_repeat = _read_password();
        }
    }

    # Modify (update) user
    eval {
        my $existing_user = MediaWords::DBI::Auth::User::ModifyUser->new(
            email                        => $user_email,
            full_name                    => $user_full_name,
            notes                        => $user_notes,
            role_ids                     => $user_role_ids,
            active                       => $user_is_active,
            password                     => $user_password,
            password_repeat              => $user_password_repeat,
            weekly_requests_limit        => $user_weekly_requests_limit,
            weekly_requested_items_limit => $user_weekly_requested_items_limit,
        );
        MediaWords::DBI::Auth::Profile::update_user( $db, $existing_user );
    };
    if ( $@ )
    {
        ERROR "Error while trying to modify user: $@";
        return 1;
    }

    INFO "User with email address '$user_email' was successfully modified.";

    return 0;
}

# Delete user; returns 0 on success, 1 on error
sub user_delete($)
{
    my ( $db ) = @_;

    my $user_email = undef;

    my Readonly $user_delete_usage = "Usage: $0" . ' --action=delete' . ' --email=jdoe@cyber.law.harvard.edu';

    GetOptions( 'email=s' => \$user_email, ) or die "$user_delete_usage\n";
    die "$user_delete_usage\n" unless ( $user_email );

    # Delete user
    eval { MediaWords::DBI::Auth::Profile::delete_user( $db, $user_email ); };
    if ( $@ )
    {
        ERROR "Error while trying to delete user: $@";
        return 1;
    }

    INFO "User with email address '$user_email' was deleted successfully.";

    return 0;
}

# List users; returns 0 on success, 1 on error
sub users_list($)
{
    my ( $db ) = @_;

    my Readonly $user_list_usage = "Usage: $0" . ' --action=list';

    GetOptions() or die "$user_list_usage\n";

    # Fetch list of users
    my $users = MediaWords::DBI::Auth::Profile::all_users( $db );

    unless ( $users )
    {
        ERROR "Unable to fetch a list of users from the database.";
        return 1;
    }

    foreach my $user ( @{ $users } )
    {
        say $user->{ email };
    }

    return 0;
}

# Show user information; returns 0 on success, 1 on error
sub user_show($)
{
    my ( $db ) = @_;

    my $user_email = undef;

    my Readonly $user_show_usage = "Usage: $0" . ' --action=show' . ' --email=jdoe@cyber.law.harvard.edu';

    GetOptions( 'email=s' => \$user_email, ) or die "$user_show_usage\n";
    die "$user_show_usage\n" unless ( $user_email );

    # Fetch information about the user
    my $db_user;
    eval { $db_user = MediaWords::DBI::Auth::Profile::user_info( $db, $user_email ); };
    if ( $@ or ( !$db_user ) )
    {
        ERROR "Unable to find user with email '$user_email'";
        return 1;
    }

    say "User ID:          " . $db_user->id();
    say "Email (username): " . $db_user->email();
    say "Full name: " . $db_user->full_name();
    say "Notes:     " . $db_user->notes();
    say "Active:    " . ( $db_user->active() ? 'yes' : 'no' );
    say "Roles:     " . join( ',', @{ $db_user->role_names() } );
    say "Global API key:   " . $db_user->global_api_key();
    say "Weekly requests limit:        " . $db_user->weekly_requests_limit();
    say "Weekly requested items limit: " . $db_user->weekly_requested_items_limit();

    return 0;
}

# List user roles; returns 0 on success, 1 on error
sub user_roles($)
{
    my ( $db ) = @_;

    my Readonly $user_roles_usage = "Usage: $0" . ' --action=roles';

    GetOptions() or die "$user_roles_usage\n";

    # Fetch roles
    my $roles = MediaWords::DBI::Auth::Roles::all_user_roles( $db );

    unless ( $roles )
    {
        ERROR "Unable to fetch a list of user roles from the database.";
        return 1;
    }

    foreach my $role ( @{ $roles } )
    {
        say $role->{ role } . "\t" . $role->{ description };
    }

    return 0;
}

# User manager
sub main
{
    my $action        = '';                                       # which action to take
    my @valid_actions = qw/add modify delete show list roles/;    # valid actions

    my Readonly $usage = "Usage: $0" . ' --action=' . join( '|', @valid_actions ) . ' ...';

    GetOptions( 'action=s' => \$action, ) or die "$usage\n";
    die "$usage\n" unless ( grep { $_ eq $action } @valid_actions );

    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    my $db = MediaWords::DB::connect_to_db();

    if ( $action eq 'add' )
    {

        # Add user
        return user_add( $db );

    }
    elsif ( $action eq 'modify' )
    {

        # Modify (update) user
        return user_modify( $db );
    }
    elsif ( $action eq 'delete' )
    {

        # Delete user
        return user_delete( $db );
    }
    elsif ( $action eq 'list' )
    {

        # List users
        return users_list( $db );
    }
    elsif ( $action eq 'show' )
    {

        # Show user information
        return user_show( $db );
    }
    elsif ( $action eq 'roles' )
    {

        # List user roles
        return user_roles( $db );
    }
    else
    {
        die "$usage\n";
        return 1;
    }
}

exit main();
