package Uc::IrcGateway::Plugin::Ctcp::Source;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :CtcpEvent('SOURCE') {
}

1;
