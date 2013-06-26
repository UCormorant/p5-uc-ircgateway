package Uc::IrcGateway::Plugin::Irc::Join;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('JOIN') {
    my ($self, $handle, $msg, $plugin) = check_params(@_);
    return () unless $self && $handle;

    my $chans = $msg->{params}[0];
    my $nick  = $handle->self->nick;
    my $login = $handle->self->login;

    for my $chan (split /,/, $chans) {
        next unless $self->check_channel( $handle, $chan );
        next if     $self->check_channel( $handle, $chan, joined => 1, silent => 1 );

        $handle->set_channels($chan) if not $handle->has_channel($chan);
        $handle->get_channels($chan)->join_users($login);
        $handle->get_channels($chan)->give_operator($login);

        # send join message
        $self->send_cmd( $handle, $handle->self, 'JOIN', $chan );

        # sever reply
        $self->send_msg( $handle, RPL_TOPIC, $chan, $handle->get_channels($chan)->topic // '' );
        $self->handle_irc_msg( $handle, "NAMES $chan" );

        push @{$msg->{success}}, $chan;
    }

    @_;
}

1;
