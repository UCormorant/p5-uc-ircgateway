package Uc::IrcGateway::Plugin::Irc::Invite;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('INVITE') {
    my ($self, $handle, $msg, $plugin) = check_params(@_);
    return () unless $self && $handle;

    my $cmd    = $msg->{command};
    my ($target, $channel) = @{$msg->{params}};

    return () unless $self->check_user($handle, $target);

    my $t_user = $handle->get_users_by_nicks($target);

    if ($self->check_channel($handle, $channel, enable => 1, silent => 1)) {
        my $chan = $handle->get_channels($channel);
        if (not $chan->has_user($handle->self->login)) {
            $self->send_msg( $handle, ERR_NOTONCHANNEL, $channel, "You're not on that channel" );
            return ();
        }
        if ($chan->has_user($t_user->login)) {
            $self->send_msg( $handle, ERR_USERONCHANNEL, $target, $channel, 'is already on channel' );
            return ();
        }
        if (not $chan->is_operator($handle->self->login)) {
            $self->send_msg( $handle, ERR_CHANOPRIVSNEEDED, $channel, "You're not channel operator" );
            return ();
        }
    }

    if ($t_user->away) {
        $self->send_msg( $handle, RPL_AWAY, $target, $t_user->away_message );
    }

    # send invite message
    $self->send_cmd( $handle, $handle->self, 'INVITE', $target, $channel );

    # send server reply
    $self->send_cmd( $handle, $handle->self, RPL_INVITING, $channel, $target );

    @_;
}

1;
