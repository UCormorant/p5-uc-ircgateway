package Uc::IrcGateway::Plugin::Irc::Ping;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :IrcEvent('PING') {
    my $self = shift;
    $self->run_hook('irc.ping.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.ping.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.ping.start' => \@_);

    $self->send_msg( $handle, 'PONG', $self->servername );

    $self->run_hook('irc.ping.finish' => \@_);
}

1;
