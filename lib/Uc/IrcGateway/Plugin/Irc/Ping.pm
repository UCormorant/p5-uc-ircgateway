package Uc::IrcGateway::Plugin::Irc::Ping;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('PING') {
    my ($self, $handle, $msg, $plugin) = @_;
    return () unless $self && $handle;

    @_;
}

1;
