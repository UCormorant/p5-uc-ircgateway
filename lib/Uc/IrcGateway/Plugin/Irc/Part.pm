package Uc::IrcGateway::Plugin::Irc::Part;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('PART') {
    my ($self, $handle, $msg, $plugin) = check_params(@_);
    return () unless $self && $handle;

    my ($chans, $text) = @{$msg->{params}};
    my $login = $handle->self->login;

    for my $chan (split /,/, $chans) {
        next unless $self->check_channel( $handle, $chan, joined => 1 );

        $handle->get_channels($chan)->part_users($login);

        # send part message
        $self->send_cmd( $handle, $handle->self, 'PART', $chan, $text );

        delete $handle->channels->{$chan} if !$handle->get_channels($chan)->user_count;
        push @{$msg->{success}}, $chan;
    }

    @_;
}

1;
