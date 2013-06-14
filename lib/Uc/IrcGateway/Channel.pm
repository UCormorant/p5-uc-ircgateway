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


=head1 DESCRIPTION


=head1 INTERFACE


=head1 BUGS AND LIMITATIONS

No bugs have been reported.


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
