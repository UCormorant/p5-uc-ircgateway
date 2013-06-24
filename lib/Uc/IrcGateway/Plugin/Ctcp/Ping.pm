package Uc::IrcGateway::Plugin::Ctcp::Ping;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :CtcpEvent('PING') {
}

1;
