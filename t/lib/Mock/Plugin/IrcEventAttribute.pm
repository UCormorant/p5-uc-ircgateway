package Mock::Plugin::IrcEventAttribute;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub event_foo :IrcEvent('FOO') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;
}

sub event_bar :IrcEvent('BAR') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;
}

sub event_baz :IrcEvent('BAZ') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;
}

1;
