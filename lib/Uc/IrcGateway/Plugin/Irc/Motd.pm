package Uc::IrcGateway::Plugin::Irc::Motd;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :IrcEvent('MOTD') {
    my $self = shift;
    $self->run_hook('irc.motd.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.motd.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.motd.start' => \@_);

    $msg->{response} = {};
    $msg->{response}{servername} = $self->servername;

    my $missing = 1;
    if (-e $self->motd) {
        my $fh = $self->motd->open("<:encoding(@{[$self->charset]})");
        if (defined $fh) {
            $missing = 0;
            $self->send_reply( $handle, $msg, 'RPL_MOTDSTART' );
            my $i = 0;
            while (my $line = $fh->getline) {
                chomp $line;
                $msg->{response}{line} = $line;
                $self->send_reply( $handle, $msg, 'RPL_MOTD' );
            }
            $self->send_reply( $handle, $msg, 'RPL_ENDOFMOTD' );
        }
    }
    if ($missing) {
        $self->send_reply( $handle, $msg, 'ERR_NOMOTD' );
    }

    $self->run_hook('irc.motd.finish' => \@_);
}

1;
