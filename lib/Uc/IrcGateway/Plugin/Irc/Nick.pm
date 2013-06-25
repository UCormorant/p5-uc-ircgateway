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
        $user->nick($nick);
        $user->update;
    }
    elsif (defined $user) {
        # finish register user
        $user->nick($nick);
        $user->register($handle);
        $msg->{registered} = 1;
        $self->welcome_message( $handle );
    }
    else {
        # start register user
        $handle->self(Uc::IrcGateway::TempUser->new( nick => $nick ));
    }

    @_;
}

1;
