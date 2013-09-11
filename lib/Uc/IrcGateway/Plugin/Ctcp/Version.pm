package Uc::IrcGateway::Plugin::Ctcp::Version;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :CtcpEvent('VERSION') {
    my $self = shift;
    $self->run_hook('ctcp.version.begin' => \@_);

        action($self, @_);

    $self->run_hook('ctcp.version.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('ctcp.version.start' => \@_);

    $self->run_hook('ctcp.version.finish' => \@_);
}

1;
