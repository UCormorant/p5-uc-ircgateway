package Uc::IrcGateway::Plugin::Irc::Away;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :IrcEvent('AWAY') {
    my $self = shift;
    $self->run_hook('irc.away.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.away.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.away.start' => \@_);

    $msg->{response}{text} = $msg->{params}[0] // '';
    $handle->self->away($msg->{response}{text} eq '' ? 0 : 1);
    $handle->self->away_message($msg->{response}{text});

    $self->run_hook('irc.away.before_reply' => \@_);
    $self->send_reply( $handle, $msg, 'RPL_UNAWAY' )  if not $handle->self->away;
    $self->send_reply( $handle, $msg, 'RPL_NOWAWAY' ) if     $handle->self->away;

    $self->run_hook('irc.away.finish' => \@_);
}

1;
