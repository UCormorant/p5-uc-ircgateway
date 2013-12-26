package Uc::IrcGateway::Plugin::AutoRegisterUser;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub register_user :Method {
    my $plugin = shift;
    my $self = shift;
    my ($handle, $user) = @_;
    return 1 if $user->isa('Uc::IrcGateway::User');

    $self->run_hook('before_register_user' => \@_);
    $user->register($handle);
    $self->run_hook('after_register_user' => \@_);
    $self->send_welcome($handle);
    return 1;
}

1;
