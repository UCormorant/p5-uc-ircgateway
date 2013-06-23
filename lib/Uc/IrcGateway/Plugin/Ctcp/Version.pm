package Uc::IrcGateway::Plugin::Ctcp::Version;
use 5.014;
use warnings;
use utf8;
use parent 'Class::Component::Plugin';

sub action :CtcpEvent('VERSION') {
}
