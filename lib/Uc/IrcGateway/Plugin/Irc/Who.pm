package Uc::IrcGateway::Plugin::Irc::Who;
use 5.014;
use warnings;
use utf8;
use parent 'Class::Component::Plugin';

sub action :IrcEvent('WHO') {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

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
            my $c_name = $channel->mode->{p} ? '*' : $channel->name;
            for my $u ($handle->get_users($channel->login_list)) {
                my $mode = $u->mode->{a} ? 'G' : 'H';
                $mode .= "*" if $u->mode->{o}; # server operator
                $mode .= $channel->is_operator($u->login) ? '@' : $channel->is_speaker($u->login) ? '+' : '';
                $self->send_msg( $handle, RPL_WHOREPLY, $c_name, $u->login, $u->host, $u->server, $u->nick, $mode, '0 '.$u->realname);
            }
            $self->send_msg( $handle, RPL_ENDOFWHO, $channel->name, 'END of /WHO List');
        }
    }
    else {
        my $u = $handle->get_users($mask);
        if ($u) {
            my $mode = $u->mode->{a} ? 'G' : 'H';
            $mode .= "*" if $u->mode->{o}; # server operator
            $self->send_msg( $handle, RPL_WHOREPLY, '*', $u->login, $u->host, $u->server, $u->nick, $mode, '0 '.$u->realname);
        }
        $self->send_msg( $handle, RPL_ENDOFWHO, '*', 'END of /WHO List');
    }

    @_;
}
