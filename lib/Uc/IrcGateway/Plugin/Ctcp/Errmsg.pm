package Uc::IrcGateway::Plugin::Ctcp::Errmsg;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :CtcpEvent('ERRMSG') {
}

1;
