package Uc::IrcGateway::Plugin::Irc::Kick;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('KICK') {
}

1;
