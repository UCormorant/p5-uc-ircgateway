package Uc::IrcGateway::Plugin::Irc::Kick;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('KICK') {
    my ($self, $handle, $msg, $plugin) = check_params(@_);
    return () unless $self && $handle;

    @_;
}

1;
