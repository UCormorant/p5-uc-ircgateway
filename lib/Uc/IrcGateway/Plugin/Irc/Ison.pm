package Uc::IrcGateway::Plugin::Irc::Ison;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('ISON') {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

    my @users;
    for my $nick (@{$msg->{params}}) {
        push @users, $nick if $handle->has_user($nick);
    }

    $self->send_msg( $handle, RPL_ISON, join ' ', @users );

    @_;
}

1;
