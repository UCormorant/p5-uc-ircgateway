package Uc::IrcGateway::Component::AutoRegisterUser;
use 5.014;
use Uc::IrcGateway::Common;
use Scalar::Util qw(refaddr);

sub register_user {
    my $self = shift;
    my ($handle, $user) = @_;
    return 1 if $user->isa('Uc::IrcGateway::User');

    $self->run_hook('before_register_user' => \@_);
    $user->register($handle);
    $self->run_hook('after_register_user' => \@_);

    $self->log($handle, info => sprintf "handle{%s} is registered as '%s'",
        refaddr $handle,
        $handle->self->to_prefix,
    );

    $self->send_welcome($handle);
    return 1;
}

1;
