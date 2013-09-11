package Uc::IrcGateway::Plugin::Irc::Part;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('PART') {
    my $self = shift;
    $self->run_hook('irc.part.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.part.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.part.start' => \@_);

    for my $channel (split /,/, $msg->{params}[0]) {
        next unless $self->check_channel( $handle, $channel, joined => 1 );

        $handle->get_channels($channel)->part_users($handle->self->login);

        # send part message
        $self->send_cmd( $handle, $handle->self, 'PART', $channel, $msg->{params}[1] );

        delete $handle->channels->{$channel} if !$handle->get_channels($channel)->user_count;
        push @{$msg->{success}}, $channel;
    }

    $self->run_hook('irc.part.finish' => \@_);
}

1;
