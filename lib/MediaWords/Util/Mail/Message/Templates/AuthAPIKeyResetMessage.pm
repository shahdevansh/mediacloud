package MediaWords::Util::Mail::Message::Templates::AuthAPIKeyResetMessage;

use strict;
use warnings;

use parent 'MediaWords::Util::Mail::Message';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.util.mail_message.templates' );

sub new
{
    my ( $class, $args ) = @_;

    my $self = {};
    bless $self, $class;

    # Inline::Python will throw very unfriendly errors on missing arguments, so double-check here
    unless ( $args->{ to } )
    {
        die "'to' is unset.";
    }
    unless ( $args->{ full_name } )
    {
        die "'full_name' is unset.";
    }

    $self->{ python_message } =
      MediaWords::Util::Mail::Message::Templates::AuthAPIKeyResetMessage::AuthAPIKeyResetMessage->new(
        $args->{ to },
        $args->{ full_name },
      );

    return $self;
}

1;
