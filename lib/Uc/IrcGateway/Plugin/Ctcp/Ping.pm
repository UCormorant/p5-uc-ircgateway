package Uc::IrcGateway::Plugin::Ctcp::Ping;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :CtcpEvent('PING') {
    my $self = shift;
    $self->run_hook('ctcp.ping.begin' => \@_);

        action($self, @_);

    $self->run_hook('ctcp.ping.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('ctcp.ping.start' => \@_);

    $self->run_hook('ctcp.ping.finish' => \@_);
}

1;
