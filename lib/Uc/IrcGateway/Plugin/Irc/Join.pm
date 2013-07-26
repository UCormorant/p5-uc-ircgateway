package Uc::IrcGateway::Plugin::Irc::Join;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('JOIN') {
    my $self = shift;
    $self->run_hook('irc.join.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.join.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.join.start' => \@_);

    for my $channel (split /,/, $msg->{params}[0]) {
        next unless $self->check_channel( $handle, $channel );
        next if     $self->check_channel( $handle, $channel, joined => 1, silent => 1 );

        $handle->set_channels($channel) if not $handle->has_channel($channel);

        $msg->{response} = {};
        $msg->{response}{nick}    = $handle->self->nick;
        $msg->{response}{login}   = $handle->self->login;
        $msg->{response}{channel} = $channel;
        $msg->{response}{topic} = $handle->get_channels($channel)->topic // '';

        $self->run_hook('irc.join.before_join_channel' => \@_);

        $handle->get_channels($channel)->join_users($msg->{response}{login});
        $handle->get_channels($channel)->give_operator($msg->{response}{login});

        $self->run_hook('irc.join.before_reply' => \@_);

        # send join message
        $self->send_cmd( $handle, $handle->self, 'JOIN', $msg->{response}{channel} );

        # sever reply
        $self->send_reply( $handle, $msg, 'RPL_TOPIC' ) if $msg->{response}{topic};
        $self->handle_irc_msg( $handle, "NAMES $msg->{response}{channel}" );

        push @{$msg->{success}}, $msg->{response};
    }

    $self->run_hook('irc.join.finish' => \@_);
}

1;
