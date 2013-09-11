package Mock::Plugin::OptionalFeatures;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub start :Hook('irc.ison.start') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;

    for my $nick (@{$msg->{params}}) {
        next unless $nick eq 'awaynick';
        unless ($self->check_user($handle, $nick, silent => 1)) {
            my $user = $handle->set_user(
                login => $nick,
                nick  => $nick,
            );

            $user->away_message('Gone.');
            $user->away(1);
            $user->update;
        }
    }
}

1;
