package Uc::IrcGateway::Plugin::Irc::Away;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('AWAY') {
    my ($self, $handle, $msg) = @_;
    return () unless $self && $handle;

    my $cmd  = $msg->{command};
    my $text = $msg->{params}[0];

    $handle->self->mode->{a} = $text eq '' ? 0 : 1;
    $self->send_cmd( $handle, $self->to_prefix, RPL_UNAWAY,  'You are no longer marked as being away' ) if not $handle->self->mode->{a};
    $self->send_cmd( $handle, $self->to_prefix, RPL_NOWAWAY, 'You have been marked as being away' )     if     $handle->self->mode->{a};

    @_;
}

1;
