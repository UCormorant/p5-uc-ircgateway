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
    my @motd_lines;
    if (defined $self->motd_text) {
        $missing = 0;
        push @motd_lines, split qr{$/}, $self->motd_text;
    }
    elsif (-e $self->motd_file) {
        my $fh = $self->motd_file->open("<:encoding(@{[$self->charset]})");
        if (defined $fh) {
            $missing = 0;
            while (my $line = $fh->getline) {
                chomp $line;
                push @motd_lines, $line;
            }
        }
    }

    if ($missing) {
        $self->send_reply( $handle, $msg, 'ERR_NOMOTD' );
    }
    else {
        $self->send_reply( $handle, $msg, 'RPL_MOTDSTART' );
        for my $line (@motd_lines) {
            $msg->{response}{text} = $line;
            $self->send_reply( $handle, $msg, 'RPL_MOTD' );
        }
        $self->send_reply( $handle, $msg, 'RPL_ENDOFMOTD' );
    }

    $self->run_hook('irc.motd.finish' => \@_);
}

1;
