package Uc::IrcGateway::Plugin::Irc::Motd;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('MOTD') {
    my ($self, $handle, $msg) = @_;
    my $missing = 1;
    if (-e $self->motd) {
        my $fh = $self->motd->open("<:encoding(@{[$self->charset]})");
        if (defined $fh) {
            $missing = 0;
            $self->send_msg( $handle, RPL_MOTDSTART, "- @{[$self->servername]} Message of the day - " );
            my $i = 0;
            while (my $line = $fh->getline) {
                chomp $line;
                $self->send_msg( $handle, RPL_MOTD, "- $line" );
            }
            $self->send_msg( $handle, RPL_ENDOFMOTD, 'End of /MOTD command' );
        }
    }
    if ($missing) {
        $self->send_msg( $handle, ERR_NOMOTD, 'MOTD File is missing' );
    }

    @_;
}

1;
