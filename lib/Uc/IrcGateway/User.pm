package Uc::IrcGateway::User;

use 5.014;
use warnings;
use utf8;

use Carp qw(croak);

our %MODE_TABLE;
our @USER_PROP;

BEGIN {
    our %MODE_TABLE = (
        away           => 'a', # Away
        invisible      => 'i', # Invisible
        allow_wallops  => 'w', # allow Wallops receiving
        allow_s_notice => 's', # allow Server notice receiving
        restricted     => 'r', # Restricted user connection
        operator       => 'o', # Operator flag
        local_operator => 'O', # local Operator flag
    );
    our @USER_PROP = (qw(
        login nick password realname host addr server
        userinfo away_message last_modified
    ), sort keys %MODE_TABLE);
}
use Class::Accessor::Lite rw => \@USER_PROP;

# constructer

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;

    bless +{
        login => '*',
        nick => '*',
        password => '',
        realname => '*',
        host => '0',
        addr => '0',
        server => '0',

        %args,
    }, $class;
}

# other method

sub bind {
    my ($self, $handle, %opt) = @_;

    if (defined $handle && $handle->isa('Uc::IrcGateway::Connection')) {
        $self->{bind} = $handle;
        $self->save if $opt{save};
    }

    return $self->{bind};
}

sub save {
    my $self = $_[0];

    croak "user registration error: nick is not defined"  if !$self->nick;
    croak "user registration error: login is not defined" if !$self->login;

    croak "this user does not bind to a handle: { login => @{[ $self->login ]}, nick => @{[ $self->nick ]} }"
        if not defined $self->{bind} or not $self->{bind}->isa('Uc::IrcGateway::Connection');

    $self->bind->schema->update_or_create('user', $self->user_prop)
}

sub to_prefix {
    sprintf "%s!%s@%s", $_[0]->nick, $_[0]->login, $_[0]->host;
}

sub user_prop {
    { map { $_ => $_[0]{$_} } @{$_[0]}{@USER_PROP} };
}

sub mode_string {
    join '', map { $_[0]->{$_} ? $MODE_TABLE{$_} : () } sort keys @{$_[0]}{keys %MODE_TABLE};
}


1; # Magic true value required at end of module
__END__

=head1 NAME

Uc::IrcGateway::User - User Object for Uc::IrcGateway


=head1 DESCRIPTION


=head1 INTERFACE


=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
L<https://github.com/UCormorant/p5-uc-ircgateway/issues>


=head1 SEE ALSO

=item L<Uc::IrcGateway>


=head1 AUTHOR

U=Cormorant  C<< <u@chimata.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011-2013, U=Cormorant C<< <u@chimata.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
