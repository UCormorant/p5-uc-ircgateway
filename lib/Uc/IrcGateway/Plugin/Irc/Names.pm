package Uc::IrcGateway::Plugin::Irc::Names;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :IrcEvent('NAMES') {
    my $self = shift;
    $self->run_hook('irc.names.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.names.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.names.start' => \@_);

    my $chans = $msg->{params}[0] || join ',', sort $handle->channel_list;
    my $server = $msg->{params}[1];

    if ($server) {
        # サーバマスク指定は対応予定なし
        $self->send_msg( $handle, ERR_NOSUCHSERVER, $server, 'No such server' );
        return ();
    }

    for my $chan (split /,/, $chans) {
        next unless $self->check_channel( $handle, $chan, enable => 1 );

        my $c = $handle->get_channels($chan);
        my $c_mode = $c->secret ? '@' : $c->private ? '*' : '=';

        my @users_list;
        for my $user ($c->users) {
            my $u_login = $user->login;
            my $u_state = $c->is_operator($u_login) ? '@' : $c->is_speaker($u_login) ? '+' : '';
            push @users_list, [$user->nick, $u_state];
        }

        $msg->{response} = {};
        $msg->{response}{channel} = $chan;
        $msg->{response}{channel_mode} = $c_mode;
        $msg->{response}{nick} = [];
        $msg->{response}{user_state} = [];
        map {
            push @{$msg->{response}{nick}},      $_->[0];
            push @{$msg->{response}{user_state}}, $_->[1];
        } sort { $a->[0] cmp $b->[0] } @users_list;

        $self->send_reply( $handle, $msg, 'RPL_NAMREPLY' );
        $self->send_reply( $handle, $msg, 'RPL_ENDOFNAMES' );
    }

    $self->run_hook('irc.names.finish' => \@_);
}

1;
