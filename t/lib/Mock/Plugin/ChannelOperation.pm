package Mock::Plugin::ChannelOperation;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub start :Hook('irc.invite.start') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;

    unless ($self->check_user($handle, $msg->{params}[0], silent => 1)) {
        $handle->set_user(
            login => $msg->{params}[0],
            nick  => $msg->{params}[0],
        );
    }
}

sub finish :Hook('irc.invite.finish') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;

    my $user = $msg->{response}{target_user};
    my $chan = $msg->{response}{target_channel};

    $chan->join_users($user);
}

1;
