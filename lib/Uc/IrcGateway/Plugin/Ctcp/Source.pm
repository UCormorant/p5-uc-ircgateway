package Uc::IrcGateway::Plugin::Ctcp::Source;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :CtcpEvent('SOURCE') {
    my $self = shift;
    $self->run_hook('ctcp.source.begin' => \@_);

        action($self, @_);

    $self->run_hook('ctcp.source.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('ctcp.source.start' => \@_);

    $self->run_hook('ctcp.source.finish' => \@_);
}

1;
