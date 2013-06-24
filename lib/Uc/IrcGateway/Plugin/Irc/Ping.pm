package Uc::IrcGateway::Plugin::Irc::Ping;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('PING') {
}

1;
