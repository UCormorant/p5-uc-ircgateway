package Uc::IrcGateway::Plugin::Irc::Ison;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('ISON') {
    my $self = shift;
    $self->run_hook('irc.invite.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.invite.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.ison.start' => \@_);

    my @users;
    for my $nick (@{$msg->{params}}) {
        push @users, $nick if $handle->has_user($nick);
    }

    # TODO: inflated_sprintf format
    $msg->{response}{nick} = join ", ", @users;

    $self->run_hook('irc.ison.before_reply' => \@_);
    $self->send_reply( $handle, $msg, 'RPL_ISON' );

    $self->run_hook('irc.ison.finish' => \@_);
}

1;
