package Uc::IrcGateway::Plugin::Irc::Nick;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('NICK') {
    my ($self, $handle, $msg, $plugin) = @_;
    return () unless $self && $handle;

    my $cmd  = $msg->{command};
    my $nick = $msg->{params}[0];
    my $user = $handle->self;

    if ($nick eq '') {
        $self->send_msg( $handle, ERR_NONICKNAMEGIVEN, 'No nickname given' );
        return ();
    }
    elsif (not $nick =~ /$REGEX{nickname}/) {
        $self->send_msg( $handle, ERR_ERRONEUSNICKNAME, $nick, 'Erroneous nickname' );
        return ();
    }
    elsif ($handle->has_nick($nick) && defined $user && $handle->lookup($nick) ne $user->login) {
        $self->send_msg( $handle, ERR_NICKNAMEINUSE, $nick, 'Nickname is already in use' );
        return ();
    }

    if (defined $user && $user->nick) {
        # change nick
        $self->send_cmd( $handle, $user, $cmd, $nick );
        $handle->del_lookup($user->nick);
        $user->nick($nick);
        $handle->set_users($user);
    }
    elsif (defined $user) {
        # finish register user
        $user->nick($nick);
        $user->registered(1);
        $msg->{registered} = 1;
        $handle->set_users($user);
        $self->welcome_message( $handle );
    }
    else {
        # start register user
        $user = Uc::IrcGateway::User->new(
            nick => $nick, login => '*', realname => '*',
            host => '*', addr => '*', server => '*',
        );
        $handle->self($user);
    }

    @_;
}

1;
