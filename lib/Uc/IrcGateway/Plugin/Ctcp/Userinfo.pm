package Uc::IrcGateway::Plugin::Ctcp::Userinfo;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :CtcpEvent('USERINFO') {
    my $self = shift;
    $self->run_hook('ctcp.userinfo.begin' => \@_);

        action($self, @_);

    $self->run_hook('ctcp.userinfo.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('ctcp.userinfo.start' => \@_);

    my ($cmd, $orig_cmd) = @{$msg}{qw/command orig_command/};
    my $prefix = $msg->{prefix};
    my $target = $msg->{target};
    my $param  = $msg->{params}[0];

    my $user = $handle->get_users_by_nicks($target);
    $self->send_ctcp_reply( $handle, $user, $cmd, $param ) unless $msg->{silent};

    $self->run_hook('ctcp.userinfo.finish' => \@_);
}

1;
