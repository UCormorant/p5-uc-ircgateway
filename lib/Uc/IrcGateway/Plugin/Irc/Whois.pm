package Uc::IrcGateway::Plugin::Irc::Whois;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('WHOIS') {
    my $self = shift;
    $self->run_hook('irc.whois.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.whois.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.whois.start' => \@_);

    my @nick_list = map { $self->check_user($handle, $_) ? $_ : () } split /,/, $msg->{params}[0];

    # TODO: mask (ワイルドカード)
    for my $user ($handle->get_users_by_nicks(@nick_list)) {
        next unless $user;

        my $channels = '';
        my @channel_list = ();
        my $channels_test = mk_msg($self->to_prefix, RPL_WHOISCHANNELS, $user->nick, '');
        for my $chan ($handle->who_is_channels($user->login)) {
            if (length "$channels_test$channels$chan$CRLF" > $MAXBYTE) {
                chop $channels;
                push @channel_list, $channels;
                $channels = '';
            }
            $channels .= "$chan ";
        }
        push @channel_list, $channels if chop $channels;

        $self->send_msg( $handle, RPL_AWAY, $user->nick, $user->away_message ) if $user->away;
        $self->send_msg( $handle, RPL_WHOISUSER, $user->nick, $user->login, $user->host, '*', $user->realname );
        $self->send_msg( $handle, RPL_WHOISSERVER, $user->nick, $user->server, $user->server );
        $self->send_msg( $handle, RPL_WHOISOPERATOR, $user->nick, 'is an IRC operator' ) if $user->operator;
        $self->send_msg( $handle, RPL_WHOISIDLE, $user->nick, time - $user->last_modified, 'seconds idle' );
        $self->send_msg( $handle, RPL_WHOISCHANNELS, $user->nick, $_ ) for @channel_list;
        $self->send_msg( $handle, RPL_ENDOFWHOIS, $user->nick, 'End of /WHOIS list' );
    }

    $self->run_hook('irc.whois.finish' => \@_);
}

1;
