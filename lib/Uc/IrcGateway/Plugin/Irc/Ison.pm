package Uc::IrcGateway::Plugin::Irc::Ison;
use 5.014;
use warnings;
use utf8;
use parent 'Class::Component::Plugin';

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
