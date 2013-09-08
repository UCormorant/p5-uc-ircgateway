package Uc::IrcGateway::Plugin::Irc::Kick;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('KICK') {
    my $self = shift;
    $self->run_hook('irc.kick.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.kick.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.kick.start' => \@_);

    my @channels = grep { $_ } split /,/, $msg->{params}[0];
    my @users    = grep { $_ } split /,/, $msg->{params}[1];

    for my $channel (@channels) {
        next unless $self->check_channel( $handle, $channel, joined => 1, operator => 1 );

#           ERR_BADCHANMASK

        my @nick_list = map { $self->check_user( $handle, $_ ) ? $_ : () } @users;

        for my $user ($handle->get_users_by_nicks(@nick_list)) {
            next unless $user;

            $msg->{response} = {};
            $msg->{response}{channel} = $channel;
            $msg->{response}{nick}    = $user->nick;
            $msg->{response}{comment} = $msg->{params}[2] // undef;
            $msg->{response}{target_channel} = $handle->get_channels($channel);
            $msg->{response}{target_user} = $user;

            if (not $msg->{response}{target_user}->channels(c_name => $msg->{response}{channel})) {
                $self->send_reply( $handle, $msg, 'ERR_USERNOTINCHANNEL' );
                next;
            }

            $self->run_hook('irc.part.before_part_channel' => \@_);

            # part user
            $msg->{response}{target_channel}->part_users($user->login);

            $self->run_hook('irc.part.before_command' => \@_);

            # send kick message
            $self->send_cmd( $handle, $handle->self, 'KICK', @{$msg->{response}}{qw/channel nick comment/} );

            push @{$msg->{success}}, $msg->{response};
        }
    }

    $self->run_hook('irc.kick.finish' => \@_);
}

1;
