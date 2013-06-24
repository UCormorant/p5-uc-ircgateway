package Uc::IrcGateway::Plugin::Irc::Pong;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('PONG') {
}

1;
