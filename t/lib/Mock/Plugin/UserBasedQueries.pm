package Mock::Plugin::UserBasedQueries;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub start_who :Hook('irc.who.start') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;

    my $mask = $msg->{params}[0];
    if (is_valid_channel_name($mask) and not $handle->has_channel($mask)) {
        $handle->set_channels($mask);
        $handle->get_channels($mask)->join_users($handle->self);
    }
    elsif (not $handle->has_user($mask)) {
        $handle->set_user(
            login => $mask,
            nick  => $mask,
        );
    }
}

sub start_whois :Hook('irc.whois.start') {
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

1;
