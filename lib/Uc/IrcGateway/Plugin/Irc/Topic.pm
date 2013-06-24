package Uc::IrcGateway::Plugin::Irc::Topic;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('TOPIC') {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

    my ($chan, $topic) = @{$msg->{params}};
    return () unless $self->check_channel( $handle, $chan, enable => 1 );

    if ($topic) {
        $handle->get_channels($chan)->topic( $topic );

        # send topic message
        my $prefix = $msg->{prefix} || $handle->self;
        $self->send_cmd( $handle, $prefix, 'TOPIC', $chan, $topic );
    }
    elsif (defined $topic) {
        $self->send_msg( $handle, RPL_NOTOPIC, $chan, 'No topic is set' );
    }
    else {
        $self->send_msg( $handle, RPL_TOPIC, $chan, $handle->get_channels($chan)->topic );
    }

    @_;
}

1;
