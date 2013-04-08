package Uc::IrcGateway::User;

use 5.014;
use warnings;
use utf8;
use Any::Moose;

=ignore
methods:
properties:
options:

=cut

my @user_prop = qw(
    nick login realname host addr server
    userinfo away_message last_modified
);
# user properties
# nick     -> <nickname>
# login    -> <username>
# reakname -> <realname>
# host     -> <hostname>
# addr     -> addr at <hostname>
# server   -> <servername>
has \@user_prop => ( is => 'rw', isa => 'Maybe[Str]', required => 1, trigger => \&_user_prop_trigger_str );
# already registered flag
has 'registered' => ( is => 'rw', isa => 'Int', default => 0, trigger => \&_user_prop_trigger_int );
# user mode
has 'mode' => ( is => 'ro', isa => 'HashRef', trigger => \&_user_mode_trigger, default => sub { {
    a => 0, # Away
    i => 0, # Invisible
    w => 0, # allow Wallops receiving
    r => 0, # restricted user connection
    o => 0, # Operator flag
    O => 0, # local Operator flag
    s => 0, # allow Server notice receiving
} } );
# ctcp USERINFO message
has 'userinfo' => ( is => 'rw', isa => 'Maybe[Str]', default => '', trigger => \&_user_prop_trigger_str );
# away message
has 'away_message' => ( is => 'rw', isa => 'Maybe[Str]', default => '', trigger => \&_user_prop_trigger_str );
# for calc idle time
has 'last_modified' => ( is => 'rw', isa => 'Int', default => sub { time }, trigger => \&_user_prop_trigger_int );

__PACKAGE__->meta->make_immutable;
no Any::Moose;

sub BUILD {
    my $self = shift;
    $self->update_or_create('user', $self, { keys => 'primary' });
}

sub to_prefix {
    return sprintf "%s!%s@%s", $_[0]->nick, $_[0]->login, $_[0]->host;
}

sub mode_string {
    my $mode = $_[0]->mode;
    return '+'.join '', grep { $mode->{$_} } sort keys %$mode;
}

sub _user_prop { { map { $_ => $_[0]{$_} } @{$_[0]}{@user_prop} } }
sub _user_mode { {
    away           => $_[0]{a},
    invisible      => $_[0]{i},
    allow_wallops  => $_[0]{w},
    allow_s_notice => $_[0]{s},
    restricted     => $_[0]{r},
    operator       => $_[0]{o},
    local_operator => $_[0]{O},
} }
my @user_mode = qw(
    away Invisible allow_wallops allow_s_notice
    restricted operator local_operator
);

sub _user_prop_trigger_str {
    my ($self, $new, $old) = @_; $old //= '';
    $self->handle->schema->update('user', $self->_user_prop, { login => $self->login }) if $new ne $old;
}
sub _user_prop_trigger_int {
    my ($self, $new, $old) = @_; $old //= 0;
    $self->handle->schema->update('user', $self->_user_prop, { login => $self->login }) if $new != $old;
}
sub _user_mode_trigger {
    my ($self, $new, $old) = @_; $old //= 0;
    $self->handle->schema->update('user', $self->_user_mode, { login => $self->login }) if $new != $old;
}

1; # Magic true value required at end of module
__END__

=head1 NAME

Uc::IrcGateway::User - User Object for Uc::IrcGateway


=head1 SYNOPSIS

    use Uc::IrcGateway::User;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.


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

Uc::IrcGateway::User requires no configuration files or environment variables.


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

Please report any bugs or feature requests to
C<bug-uc-ircgateway@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


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
