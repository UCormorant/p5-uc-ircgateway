package Uc::IrcGateway::Plugin::Ctcp::Time;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :CtcpEvent('TIME') {
}

1;
