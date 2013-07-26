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
            my $c_name = $channel->private ? '*' : $channel->name;
            for my $u ($handle->get_users($channel->login_list)) {
                my $mode = $u->away ? 'G' : 'H';
                $mode .= "*" if $u->operator; # server operator
                $mode .= $channel->is_operator($u->login) ? '@' : $channel->is_speaker($u->login) ? '+' : '';
                $self->send_msg( $handle, RPL_WHOREPLY, $c_name, $u->login, $u->host, $u->server, $u->nick, $mode, '0 '.$u->realname);
            }
            $self->send_msg( $handle, RPL_ENDOFWHO, $channel->name, 'END of /WHO List');
        }
    }
    else {
        my $u = $handle->get_users($mask);
        if ($u) {
            my $mode = $u->away ? 'G' : 'H';
            $mode .= "*" if $u->operator; # server operator
            $self->send_msg( $handle, RPL_WHOREPLY, '*', $u->login, $u->host, $u->server, $u->nick, $mode, '0 '.$u->realname);
        }
        $self->send_msg( $handle, RPL_ENDOFWHO, '*', 'END of /WHO List');
    }

    $self->run_hook('irc.who.finish' => \@_);
}

1;
