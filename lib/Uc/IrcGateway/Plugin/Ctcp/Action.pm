package Uc::IrcGateway::Plugin::Ctcp::Action;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :CtcpEvent('ACTION') {
    my $self = shift;
    $self->run_hook('ctcp.action.begin' => \@_);

        action($self, @_);

    $self->run_hook('ctcp.action.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('ctcp.action.start' => \@_);

    $self->run_hook('ctcp.action.finish' => \@_);
}

1;
