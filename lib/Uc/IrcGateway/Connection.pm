package Uc::IrcGateway::Connection;

use 5.014;
use warnings;
use utf8;
use Any::Moose;

use Carp;
use Path::Class;
use Scalar::Util qw(refaddr);

use Uc::IrcGateway::Structure;

=ignore
methods:
    HASHREF   = channels()
    CHANNELS  = get_channels( CHANNAME [, CHANNAME, ...] )
    CHANNELS  = set_channels( CHANNAME => CHANNEL [, CHANNAME => CHANNEL, ...] )
    CHANNEL   = del_channels( CHANNAME [, CHANNAME, ...] )
    BOOL      = has_channel( CHANNAME )
    CHANNAMES = channel_list()
    CHANNAMES = joined_channel_list( USERID )

properties:
    self     -> Uc::IrcGateway::User # connection's userdata
    channels -> { CHANNAME => Uc::IrcGateway::Channel } # hash of channels

options:
    same as AnyEvent::Handle

=cut

extends 'AnyEvent::Handle', any_moose('::Object');
# connection's user object
has 'self' => ( is => 'rw', isa => 'Uc::IrcGateway::User' );
# connection's structure object
has 'schema' => ( is => 'ro', isa => 'Uc::IrcGateway::Structure', lazy => 1, builder => sub { $_[0]->bind_structure } );
# some options you need
has 'options' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
# DESTORY code
has 'on_destroy' => ( is => 'rw', isa => 'CodeRef' );
# channel list
has 'channels' => (
    is => 'rw', traits => ['Hash'], default => sub { {} }, init_arg => undef,
    isa => 'HashRef[Uc::IrcGateway::Channel]', handles => {
        get_channels => 'get',
        set_channels => 'set',
        del_channels => 'delete',
        has_channel  => 'defined',
        channel_list => 'keys',
} );
# login user list
has 'users' => (
    is => 'rw', traits => ['Hash'], default => sub { {} }, init_arg => undef,
    isa => 'HashRef[Uc::IrcGateway::User]', handles => {
        get_users => 'get',
        has_user  => 'defined',
        user_list => 'keys',
} );
# lookup (nick => login list)
has 'nicks' => (
    is => 'rw', traits => ['Hash'], default => sub { {} }, init_arg => undef,
    isa => 'HashRef', handles => {
        lookup     => 'get',
        set_lookup => 'set',
        del_lookup => 'delete',
        has_nick   => 'defined',
        nick_list  => 'keys',
} );

#__PACKAGE__->meta->make_immutable;
no Any::Moose;

sub new {
    my $class = shift;
    my $obj   = $class->SUPER::new( @_ );
    my $self  = $class->meta->new_object(
        __INSTANCE__ => $obj,
        @_,
    );
    while (my ($k, $v) = each %$obj) {
        $self->{$k} = $v;
    }

    return $self;
}

sub bind_structure {
    my $self = shift;
    return undef unless $self->self && $self->self->nick;
    Uc::IrcGateway::Structure->new( dbh => setup_dbh($self->self->nick) );
}

sub get_users_by_nicks {
    my $self = shift;
    my @user_list;
    push @user_list, $self->get_users($self->lookup($_ // '') // '') for @_;
    return @user_list;
}

sub set_users {
    my $self = shift;
    for my $user (@_) {
        croak "Arguments must be Uc::IrcGateway::User object" if not ref $user eq 'Uc::IrcGateway::User';
        $self->users->{$user->login} = $user;
        $self->set_lookup($user->nick, $user->login) if $user->registered;
    }

    wantarray ? @_ : scalar @_;
}

sub del_users {
    my $self = shift;
    my @del_users;
    for my $login (@_) {
        if ($self->has_user($login)) {
            my $user = delete $self->users->{$login};
            $self->del_lookup($user->nick);
            push @del_users, $user;
        }
    }

    wantarray ? @del_users : scalar @del_users;
}

sub who_is_channels {
    my ($self, $login) = @_;
    my @channels;
    # TODO: error if not $login

    for my $chan ($self->channel_list) {
        push @channels, $chan if $self->get_channels($chan)->has_user($login);
    }

    wantarray ? @channels : scalar @channels;
}

sub DESTROY {
    my $self = shift;
    my $ev = $self->on_destroy;
    $ev->($self) if ref $ev eq 'CODE';
    $self->SUPER::DESTROY();
}


1; # Magic true value required at end of module
__END__

=head1 NAME

Uc::IrcGateway::Connection - Uc::IrcGatewayのためのコネクションクラス


=head1 SYNOPSIS

    use Uc::IrcGateway::Connection;
    my $handle = Uc::IrcGateway::Connection->new( fh => $fh );

=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.


=head1 INTERFACE

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.


=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.

Uc::IrcGateway::Connection requires no configuration files or environment variables.


=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.


=head1 AUTHOR

U=Cormorant  C<< <u@chimata.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011, U=Cormorant C<< <u@chimata.org> >>. All rights reserved.

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
