package Uc::IrcGateway::Logger;

use 5.014;
use warnings;
use utf8;

use parent qw(Log::Dispatch);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->{log_level}  = +{};
    $self->{on_destroy} = +[];
    $self;
}

sub log {
    my ($self, $level, $message) = @_;
    if (exists $self->log_level->{$level}) {
        for my $code (@{$self->log_level->{$level}}) {
            ($level, $message) = $code->(@_);
        }
    }
    elsif (exists $self->log_level->{any}) {
        for my $code (@{$self->log_level->{any}}) {
            ($level, $message) = $code->(@_);
        }
    }

    $self->SUPER::log(level => $level, message => $message) if $level;
}

sub log_and_die {
    my ($self, $level, $message) = @_;
    $self->SUPER::log_and_die(level => $level, message => $message, carp_level => 3);
}

sub log_level { $_[0]->{log_level} }
sub add_log_level {
    my ($self, $level, $code) = @_;
    $self->log_level->{$level} = [] if not exists $self->log_level->{$level};
    push $self->log_level->{$level}, $code;
}

sub on_destroy {
    my ($self, $code) = @_;
    if ($code) {
        push $self->{on_destroy}, $code;
    }
    $self->{on_destroy};
}
sub DESTROY {
    my $self = shift;
    for my $code (@{$self->on_destroy}) {
        $code->($self) if ref $code eq 'CODE';
    }
}


1; # Magic true value required at end of module
__END__

=encoding utf-8

=head1 NAME

Uc::IrcGateway::Logger - Uc::IrcGatewayのためのデータロガー


=head1 SYNOPSIS

    use Uc::IrcGateway;


=head1 DESCRIPTION


=head1 INTERFACE


=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
L<https://github.com/UCormorant/p5-uc-ircgateway/issues>


=head1 AUTHOR

U=Cormorant E<lt>u@chimata.orgE<gt>


=head1 SEE ALSO

=over

=item Uc::IrcGateway L<https://github.com/UCormorant/p5-uc-ircgateway>

=back


=head1 LICENCE AND COPYRIGHT

Copyright (C) 2011-2013, U=Cormorant. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut
