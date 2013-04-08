package Uc::IrcGateway::Channel;

use 5.014;
use warnings;
use utf8;
use Any::Moose;

=ignore
methods:
    HASHREF = users()
    USERS   = get_nicks( LOGIN [, LOGIN, ...] )
    USERS   = join_users( LOGIN => NICK [, LOGIN => NICK, ...] )
    USERS   = part_users( LOGIN [, LOGIN, ...] )
    BOOL    = has_user( LOGIN )
    LOGINS  = login_list()
    NICKS   = nick_list()
    INT     = user_count()

properties:
    topic -> TOPIC # channel topic
    mode  -> { MODE => VALUE } # hash of channel mode

options:
    topic -> TOPIC # channel topic
    mode  -> { MODE => VALUE } # hash of channel mode

=cut

# channel name
has 'name'  => ( is => 'rw', isa => 'Maybe[Str]', required => 1 );
# channel topic
has 'topic' => ( is => 'rw', isa => 'Maybe[Str]', default => '' );
# user list[real => object hash] of channel
has 'users' => (
    is => 'ro', traits => ['Hash'], default => sub { {} }, init_arg => undef,
    isa => 'HashRef', handles => {
        get_nicks  => 'get',
        join_users => 'set',
        part_users => 'delete',
        has_user   => 'defined',
        login_list => 'keys',
        nick_list  => 'values',
        user_count => 'count',
} );
# channel mode
has 'mode' => ( is => 'ro', isa => 'HashRef', default => sub { {
    a => 0, # toggle the anonymous channel flag
    i => 0, # toggle the invite-only channel flag
    m => 0, # toggle the moderated channel
    n => 0, # toggle the no messages to channel from clients on the outside
    q => 0, # toggle the quiet channel flag
    p => 0, # toggle the private channel flag
    s => 0, # toggle the secret channel flag
    r => 0, # toggle the server reop channel flag
    t => 0, # toggle the topic settable by channel operator only flag;

    k => '', # set/remove the channel key (password)
    l => 0,  # set/remove the user limit to channel

    b => '', # set/remove ban mask to keep users out
    e => '', # set/remove an exception mask to override a ban mask
    I => '', # set/remove an invitation mask to automatically override the invite-only flag
} } );
# channel operator list
has 'operators' => ( is => 'ro', traits => ['Hash'], default => sub { {} }, init_arg => undef,
    isa => 'HashRef', handles => {
        give_operator    => 'set',
        deprive_operator => 'delete',
        is_operator => 'defined',
        operator_login_list => 'keys',
        operator_nick_list  => 'values',
        operator_count => 'count',
} );
# channel speaker list
has 'speakers' => ( is => 'ro', traits => ['Hash'], default => sub { {} }, init_arg => undef,
    isa => 'HashRef', handles => {
        give_voice    => 'set',
        deprive_voice => 'delete',
        is_speaker => 'defined',
        speaker_login_list => 'keys',
        speaker_nick_list  => 'values',
        speaker_count => 'count',
} );

__PACKAGE__->meta->make_immutable;
no Any::Moose;


1; # Magic true value required at end of module
__END__

=head1 NAME

Uc::IrcGateway::Channel - Channel Object for Uc::IrcGateway


=head1 SYNOPSIS

    use Uc::IrcGateway;

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

Uc::IrcGateway::Channel requires no configuration files or environment variables.


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
