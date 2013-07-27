package Uc::IrcGateway::Plugin::Irc::Nick;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :IrcEvent('NICK') {
    my $self = shift;
    $self->run_hook('irc.nick.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.nick.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.nick.start' => \@_);

    $msg->{response} = {};
    $msg->{response}{user} = $handle->self;
    $msg->{response}{nick} = $msg->{params}[0];
    my $cmd  = $msg->{command};
    my $nick = $msg->{params}[0];
    my $user = $handle->self;

    if ($msg->{params}[0] eq '') {
        $self->send_reply( $handle, $msg, 'ERR_NONICKNAMEGIVEN' );
        return;
    }
    elsif (not $msg->{params}[0] =~ /$REGEX{nickname}/) {
        $msg->{response}{nick} = $msg->{params}[0];
        $self->send_reply( $handle, $msg, 'ERR_ERRONEUSNICKNAME' );
        return;
    }
    elsif ($handle->has_nick($msg->{params}[0]) && defined $handle->self && $handle->lookup($msg->{params}[0]) ne $handle->self->login) {
        $msg->{response}{nick} = $msg->{params}[0];
        $self->send_reply( $handle, $msg, 'ERR_NICKNAMEINUSE' );
        return ();
    }

    $msg->{response}{nick} = $msg->{params}[0];

    if ($handle->self->isa('Uc::IrcGateway::User')) {
        # change nick
        $self->send_cmd( $handle, $handle->self, $msg->{command}, $msg->{response}{nick} );
        $handle->self->nick($msg->{response}{nick});
        $handle->self->update;
    }
    elsif ($handle->self->login) {
        # finish register user
        $user->nick($msg->{response}{nick});
        $user->register($handle);
        $msg->{registered} = 1;
        $self->send_welcome( $handle );
    }
    else {
        # start register user
        $handle->self->nick($msg->{response}{nick});
    }

    $self->run_hook('irc.nick.finish' => \@_);
}

1;
