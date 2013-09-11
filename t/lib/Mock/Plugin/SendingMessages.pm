package Mock::Plugin::SendingMessages;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub start :Hook('irc.privmsg.start') :Hook('irc.notice.start') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;

    for my $target (split /,/, $msg->{params}[0]) {
        if (is_valid_channel_name($target) and not $handle->has_channel($target)) {
            $handle->set_channels($target);
        }
        elsif (not $handle->has_nick($target)) {
            $handle->set_user(
                login => $target,
                nick  => $target,
            );
        }
    }
}

sub finish :Hook('irc.privmsg.finish') :Hook('irc.notice.finish') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;

    for my $res (@{$msg->{success}}) {
        $self->send_cmd( $handle, $res->{prefix}, $msg->{command}, $res->{target}, $res->{text} );
    }
}

1;
