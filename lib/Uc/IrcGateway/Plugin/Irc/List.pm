package Uc::IrcGateway::Plugin::Irc::List;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
    $config->{send_liststart} //= 0;
}

sub event :IrcEvent('LIST') {
    my $self = shift;
    $self->run_hook('irc.list.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.list.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.list.start' => \@_);

    if ($msg->{params}[1]) {
        # サーバマスク指定は対応予定なし
        $msg->{response} = {};
        $msg->{response}{server} = $msg->{params}[1];

        $self->send_reply( $handle, $msg, 'ERR_NOSUCHSERVER' );
        return;
    }

    if ($plugin->config->{send_liststart}) {
        # too old message spec
        $msg->{response} = {};
        $msg->{response}{nick} = $handle->self->nick;
        $self->send_reply( $handle, $msg, 'RPL_LISTSTART' );
    }

    my $chans = $msg->{params}[0] || join ',', sort $handle->channel_list;
    for my $channel ($handle->get_channels(split /,/, $chans)) {
        next unless $channel;
        # TODO: 自分がチャンネルメンバーの場合は表示する
        next if $channel->private or $channel->secret;
        $msg->{response} = {};
        $msg->{response}{channel} = $channel->name;
        $msg->{response}{topic}   = $channel->topic;
        $msg->{response}{visible} = scalar $channel->login_list;
        $self->send_reply( $handle, $msg, 'RPL_LIST' );

        push @{$msg->{success}}, $msg->{response};
    }
    $self->send_reply( $handle, $msg, 'RPL_LISTEND' );

    $self->run_hook('irc.list.finish' => \@_);
}

1;
