package Uc::IrcGateway::User;
use 5.014;
use parent 'Teng::Row';

sub new {
    my $class = shift;
    $class->SUPER::new(@_);
}

sub channels { # has_many
    local $_;
    my $self = shift;
    my @channels = map { $_->c_name } $self->{teng}->search('channel_user', +{ u_login => $self->login, @_ });
    $self->{teng}->search('channel', +{ name => \@channels });
}

sub operator_channels { # has_many
    my $self = shift;
    $self->channels( operator => 1, @_ );
}

sub speaker_channels { # has_many
    my $self = shift;
    $self->channels( speaker => 1, @_ );
}

sub to_prefix {
    sprintf "%s!%s@%s", $_[0]->nick, $_[0]->login, $_[0]->host;
}

sub part_from_all_channels {
    my $self = shift;
    for my $channel ($self->channels) {
        $channel->part_users($self->login);
    }
    $self;
}


1; # Magic true value required at end of module
__END__

=encoding utf8

=head1 NAME

Uc::IrcGateway::User - User Object for Uc::IrcGateway


=head1 DESCRIPTION


=head1 INTERFACE


=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
L<https://github.com/UCormorant/p5-uc-ircgateway/issues>


=head1 SEE ALSO

=over

=item L<Uc::IrcGateway>

=back


=head1 AUTHOR

U=Cormorant  C<< <u@chimata.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011-2013, U=Cormorant C<< <u@chimata.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
