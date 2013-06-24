package Uc::IrcGateway::Plugin::Ctcp::Userinfo;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :CtcpEvent('USERINFO') {
    my ($self, $handle, $msg) = @_;
    my ($cmd, $orig_cmd) = @{$msg}{qw/command orig_command/};
    my $prefix = $msg->{prefix};
    my $target = $msg->{target};
    my $param  = $msg->{params}[0];

    my $user = $handle->get_users_by_nicks($target);
    $self->send_ctcp_reply( $handle, $user, $cmd, $param ) unless $msg->{silent};

    @_;
}

1;
