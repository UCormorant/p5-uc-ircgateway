package Uc::IrcGateway::Plugin::Ctcp::Version;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :CtcpEvent('VERSION') {
}

1;
