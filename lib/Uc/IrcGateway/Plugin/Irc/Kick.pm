package Uc::IrcGateway::Plugin::Irc::Kick;
use 5.014;
use warnings;
use utf8;
use parent 'Class::Component::Plugin';

sub action :IrcEvent('KICK') {
}
