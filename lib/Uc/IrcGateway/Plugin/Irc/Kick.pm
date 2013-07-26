package Uc::IrcGateway::Plugin::Irc::Kick;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('KICK') {
    my $self = shift;
    $self->run_hook('irc.kick.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.kick.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.kick.start' => \@_);

    $self->run_hook('irc.kick.finish' => \@_);
}

1;
