package Uc::IrcGateway::Plugin::Irc::Who;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('WHO') {
    my $self = shift;
    $self->run_hook('irc.who.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.who.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.who.start' => \@_);

    my ($mask, $oper) = @{$msg->{params}};
    my @channels;

    # TODO: いまのところ channel, nick の完全一致チェックしにか対応してません
    if (!$mask || $mask eq '0') {
        @channels = grep {
            not $self->check_channel($handle, $_, joined => 1, silent => 1);
        } $handle->channel_list;
        @channels = $handle->get_channels(@channels);
    }
    elsif ($handle->has_channel($mask)) {
        @channels = $handle->get_channels($mask);
    }
    else {
        @channels = ();
    }

    if (scalar @channels) {
        for my $channel (@channels) {
            # TODO: s,p and channel menber
            my $c_name = $channel->name;
            for my $u ($channel->users) {
                my $u_login = $u->login;
                my $u_state = $u->away ? 'G' : 'H';
                $u_state .= "*" if $u->operator; # server operator
                $u_state .= $channel->is_operator($u_login) ? '@' : $channel->is_speaker($u_login) ? '+' : '';

                $msg->{response} = {};
                $msg->{response}{name} = $c_name;
                $msg->{response}{channel} = $c_name;
                $msg->{response}{user} = $u_login;
                $msg->{response}{host} = $u->host;
                $msg->{response}{server} = $u->server;
                $msg->{response}{nick} = $u->nick;
                $msg->{response}{user_state} = $u_state;
                $msg->{response}{hopcount} = 0;
                $msg->{response}{realname} = $u->realname;
                $self->send_reply( $handle, $msg, 'RPL_WHOREPLY' );
            }
            $self->send_reply( $handle, $msg, 'RPL_ENDOFWHO' );
        }
    }
    else {
        my $name = '*';
        $msg->{response} = {};
        $msg->{response}{name} = $name;

        my $u = $handle->get_users($mask);
        if ($u) {
            my $u_state = $u->away ? 'G' : 'H';
            $u_state .= "*" if $u->operator; # server operator

            $msg->{response}{channel} = $name;
            $msg->{response}{user} = $u->login;
            $msg->{response}{host} = $u->host;
            $msg->{response}{server} = $u->server;
            $msg->{response}{nick} = $u->nick;
            $msg->{response}{user_state} = $u_state;
            $msg->{response}{hopcount} = 0;
            $msg->{response}{realname} = $u->realname;
            $self->send_reply( $handle, $msg, 'RPL_WHOREPLY' );
        }
        $self->send_reply( $handle, $msg, 'RPL_ENDOFWHO' );
    }

    $self->run_hook('irc.who.finish' => \@_);
}

1;
