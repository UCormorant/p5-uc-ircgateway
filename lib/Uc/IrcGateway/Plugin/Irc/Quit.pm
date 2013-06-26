package Uc::IrcGateway::Plugin::Irc::Quit;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('QUIT') {
    my ($self, $handle, $msg, $plugin) = @_;
    return () unless $self && $handle;

    my $prefix = $msg->{prefix} || $handle->self->to_prefix;
    my $quit_msg = $msg->{params}[0];
    my ($nick, $login, $host) = split_prefix($prefix);

    # send error to accept quit # 本人には返さなくていい
    # $self->send_cmd( $handle, $prefix, 'ERROR', qq|Closing Link: $nick\[$login\@$host\] ("$quit_msg")| );

    $handle->push_shutdown; # close connection

    @_;
}

1;
