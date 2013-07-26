package Uc::IrcGateway::Plugin::Ctcp::Errmsg;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :CtcpEvent('ERRMSG') {
    my $self = shift;
    $self->run_hook('ctcp.errmsg.begin' => \@_);

        action($self, @_);

    $self->run_hook('ctcp.errmsg.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('ctcp.errmsg.start' => \@_);

    $self->run_hook('ctcp.errmsg.finish' => \@_);
}

1;
