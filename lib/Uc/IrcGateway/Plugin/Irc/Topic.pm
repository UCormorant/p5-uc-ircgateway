package Uc::IrcGateway::Plugin::Irc::Topic;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('TOPIC') {
    my $self = shift;
    $self->run_hook('irc.topic.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.topic.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.topic.start' => \@_);

    $msg->{response} = {};
    $msg->{response}{channel} = $msg->{params}[0];
    $msg->{response}{prefix}  = $msg->{prefix} || $handle->self->to_prefix;

    return unless $self->check_channel( $handle, $msg->{response}{channel}, enable => 1 );

    my $channel = $handle->get_channels($msg->{response}{channel});

    if ($msg->{params}[1]) {
        $msg->{response}{topic} = $msg->{params}[1];
        $channel->topic( $msg->{response}{topic} );
        $channel->update;

        # send topic message
        $self->send_cmd( $handle, $msg->{response}{prefix}, 'TOPIC', @{$msg->{response}}{qw/channel topic/} );
    }
    elsif (defined $msg->{params}[1]) {
        $self->send_reply( $handle, $msg, 'RPL_NOTOPIC' );
    }
    else {
        $msg->{response}{topic} = $channel->topic;
        $self->send_reply( $handle, $msg, 'RPL_TOPIC' );
    }

    $self->run_hook('irc.topic.finish' => \@_);
}

1;
