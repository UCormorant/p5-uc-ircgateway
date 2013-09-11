package Uc::IrcGateway::Plugin::Irc::Invite;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('INVITE') {
    my $self = shift;
    $self->run_hook('irc.invite.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.invite.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.invite.start' => \@_);

    return unless $self->check_user($handle, $msg->{params}[0]);

    $msg->{response} //= {};
    $msg->{response}{nick}    = $msg->{params}[0];
    $msg->{response}{channel} = $msg->{params}[1];
    $msg->{response}{target_user} = $handle->get_users_by_nicks($msg->{response}{nick});

    if ($self->check_channel($handle, $msg->{response}{channel}, enable => 1, silent => 1)) {
        $msg->{response}{target_channel} = $handle->get_channels($msg->{response}{channel});
        if (not $msg->{response}{target_channel}->has_user($handle->self->login)) {
            $self->send_reply( $handle, $msg, 'ERR_NOTONCHANNEL' );
            return;
        }
        if ($msg->{response}{target_channel}->has_user($msg->{response}{target_user}->login)) {
            $self->send_reply( $handle, $msg, 'ERR_USERONCHANNEL' );
            return;
        }
        if (not $msg->{response}{target_channel}->is_operator($handle->self->login)) {
            $self->send_reply( $handle, $msg, 'ERR_CHANOPRIVSNEEDED' );
            return;
        }
    }

    if ($msg->{response}{target_user}->away) {
        $msg->{response}{away_message} = $msg->{response}{target_user}->away_message;
        $self->run_hook('irc.invite.before_reply_away' => \@_);
        $self->send_reply( $handle, $msg, 'RPL_AWAY' );
    }

    # send invite message
    $self->run_hook('irc.invite.before_command' => \@_);
    $self->send_cmd( $handle, $handle->self, 'INVITE', @{$msg->{response}}{qw/nick channel/} );

    # send server reply
    $self->run_hook('irc.invite.before_reply' => \@_);
    $self->send_reply( $handle, $msg, 'RPL_INVITING' );

    $self->run_hook('irc.invite.finish' => \@_);
}

1;
