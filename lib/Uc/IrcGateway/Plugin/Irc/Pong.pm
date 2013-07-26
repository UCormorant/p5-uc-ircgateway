package Uc::IrcGateway::Plugin::Irc::Pong;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :IrcEvent('PONG') {
    my $self = shift;
    $self->run_hook('irc.pong.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.pong.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.pong.start' => \@_);

    $self->run_hook('irc.pong.finish' => \@_);
}

1;
