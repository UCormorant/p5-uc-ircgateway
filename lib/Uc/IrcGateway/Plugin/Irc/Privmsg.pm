package Uc::IrcGateway::Plugin::Irc::Privmsg;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('PRIVMSG') {
    my $self = shift;
    $self->run_hook('irc.privmsg.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.privmsg.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    my $notice = $msg->{command} eq 'NOTICE' ? 1 : 0;

    $notice ? $self->run_hook('irc.notice.start'  => \@_)
            : $self->run_hook('irc.privmsg.start' => \@_);

    # set plain text and ctcp
    @{$msg}{qw/plain_text ctcp/} = decode_ctcp($msg->{params}[1]);

    if (not defined $msg->{params}[1]) {
        $msg->{response} = {};
        $self->send_reply( $handle, $msg, 'ERR_NOTEXTTOSEND' ) unless $notice;
        return;
    }

    for my $target (split /,/, $msg->{params}[0]) {
        $msg->{response} = {};
        $msg->{response}{target} = $target;
        $msg->{response}{prefix} = $msg->{prefix} || $handle->self->to_prefix;
        $msg->{response}{text}   = $msg->{plain_text};

        # TODO: error
        if (0) { # WILD CARD
            if (0) { # check wild card
                # ERR_NOTOPLEVEL <mask> :No toplevel domain specified
                # ERR_WILDTOPLEVEL <mask> <mask> :Wildcard in toplevel domain
                # ERR_TOOMANYTARGETS <target> :<error code> recipients. <abort message>
                # ERR_NORECIPIENT :No recipient given (<command>)
                next;
            }
        }
        elsif (is_valid_channel_name($target)) {
            if (not $self->check_channel($handle, $target, enable => 1, silent => 1)) {
                $msg->{response}{nick} = $target;
                $self->send_reply( $handle, $msg, 'ERR_NOSUCHNICK' ) if not $notice;
                next;
            }
            if (0) { # check mode
                # ERR_CANNOTSENDTOCHAN <channel name> :Cannot send to channel
                next;
            }
            $msg->{response}{channel} = $target;
            $msg->{response}{target_is_channel} = 1;
        }
        elsif (not $self->check_user($handle, $target, silent => $notice)) {
            next;
        }
        else {
            my $user = $handle->get_users_by_nicks($target);
            $msg->{response}{nick} = $user->nick;
            $msg->{response}{away_message} = $user->away_message;
            $self->send_reply( $handle, $msg, 'RPL_AWAY' ) if $user->away;
            $msg->{response}{target_is_user} = 1;
        }

        # ctcp event
        if (scalar @{$msg->{ctcp}}) {
            for my $event (@{$msg->{ctcp}}) {
                my ($ctcp_text, $ctcp_args) = @{$event};
                $ctcp_text .= " $ctcp_args" if $ctcp_args;
                $self->handle_ctcp_msg( $handle, $ctcp_text,
                    prefix => $msg->{response}{prefix},
                    target => $msg->{response}{target},
                    orig_command => $msg->{commnad},
                    silent => $notice,
                );
            }
        }

        # push target for override method
        push @{$msg->{success}}, $msg->{response};
    }

    $notice ? $self->run_hook('irc.notice.finish'  => \@_)
            : $self->run_hook('irc.privmsg.finish' => \@_);

}

1;
