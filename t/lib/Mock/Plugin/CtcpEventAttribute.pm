package Mock::Plugin::CtcpEventAttribute;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub event_foo :CtcpEvent('FOO') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;
}

sub event_bar :CtcpEvent('BAR') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;
}

sub event_baz :CtcpEvent('BAZ') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;
}

1;
