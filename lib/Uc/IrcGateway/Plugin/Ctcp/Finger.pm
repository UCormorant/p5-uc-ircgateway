package Uc::IrcGateway::Plugin::Ctcp::Finger;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :CtcpEvent('FINGER') {
}

1;
