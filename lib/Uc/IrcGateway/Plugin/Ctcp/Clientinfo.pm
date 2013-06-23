package Uc::IrcGateway::Plugin::Ctcp::Clientinfo;
use 5.014;
use warnings;
use utf8;
use parent 'Class::Component::Plugin';

sub action :CtcpEvent('CLIENTINFO') {
    my ($self, $handle, $msg) = @_;
    my ($cmd, $orig_cmd) = @{$msg}{qw/command orig_command/};
    my $prefix = $msg->{prefix};
    my $target = $msg->{target};
    my $param  = $msg->{params}[0];

    my $user = $handle->get_users_by_nicks($target);
    $self->send_ctcp_reply( $handle, $user, $cmd, $param ) unless $msg->{silent};

    @_;
}
