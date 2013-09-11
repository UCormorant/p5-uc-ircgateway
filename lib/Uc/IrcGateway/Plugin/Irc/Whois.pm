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

        $msg->{response} = {};
        $msg->{response}{nick} = $user->nick;
        $msg->{response}{user} = $user->login;
        $msg->{response}{host} = $user->host;
        $msg->{response}{realname} = $user->realname;
        $msg->{response}{server} = $user->server;
        $msg->{response}{server_info} = $user->server;
        $msg->{response}{idle} = time - $user->last_modified;
        $msg->{response}{away_message} = $user->away_message;

        my $u_login = $user->login;
        for my $c ($user->channels) {
            my $u_state = $c->is_operator($u_login) ? '@' : $c->is_speaker($u_login) ? '+' : '';
            push @{$msg->{response}{channel}},    $c->name;
            push @{$msg->{response}{user_state}}, $u_state;
        }

        $self->send_reply( $handle, $msg, 'RPL_AWAY' ) if $user->away;
        $self->send_reply( $handle, $msg, 'RPL_WHOISUSER' );
        $self->send_reply( $handle, $msg, 'RPL_WHOISSERVER' );
        $self->send_reply( $handle, $msg, 'RPL_WHOISOPERATOR' ) if $user->operator;
        $self->send_reply( $handle, $msg, 'RPL_WHOISIDLE' );
        $self->send_reply( $handle, $msg, 'RPL_WHOISCHANNELS' ) if exists $msg->{response}{channel};
        $self->send_reply( $handle, $msg, 'RPL_ENDOFWHOIS' );
    }

    $self->run_hook('irc.whois.finish' => \@_);
}

1;
