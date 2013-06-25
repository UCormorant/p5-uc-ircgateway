package Uc::IrcGateway::Plugin::Irc::User;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('USER') {
    my ($self, $handle, $msg, $plugin) = check_params(@_);
    return () unless $self && $handle;

    my ($login, $host, $server, $realname) = @{$msg->{params}};
    my $cmd  = $msg->{command};
    my $user = $handle->self;
    if (defined $user && ref $user->isa('Uc::IrcGateway::User')) {
        $self->send_msg( $handle, ERR_ALREADYREGISTRED, 'Unauthorized command (already registered)' );
        return ();
    }

    $host ||= '0'; $server ||= '*'; $realname ||= '';
    if (defined $user) {
        $user->login($login);
        $user->realname($realname);
        $user->host($host);
        $user->addr($self->host);
        $user->server($server);
        $user->register($handle);
        $msg->{registered} = 1;
        $self->send_welcome( $handle );
    }
    else {
        $handle->self(Uc::IrcGateway::TempUser->new(
            login => $login, realname => $realname,
            host => $host, addr => $self->host, server => $server,
        ));
    }

    @_;
}

1;
