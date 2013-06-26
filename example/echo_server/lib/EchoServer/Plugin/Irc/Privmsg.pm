package EchoServer::Plugin::Irc::Privmsg;
use 5.014;
use parent 'Uc::IrcGateway::Plugin::Irc::Privmsg';
use Uc::IrcGateway::Common;

sub action :IrcEvent('PRIVMSG') {
    my ($self, $handle, $msg, $plugin) = check_params(shift->SUPER::action(@_));
    return unless $self && $handle;

    my ($msgtarget, $text) = @{$msg->{params}};

    for my $target (@{$msg->{success}}) {
        # send privmsg message to yourself
        $self->send_cmd( $handle, $handle->self, 'PRIVMSG', $target, $text );
    }

    @_;
}

1;
