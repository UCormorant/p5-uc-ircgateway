package Uc::IrcGateway::Channel;
use 5.014;
use parent 'Teng::Row';

## channel mode
#has 'mode' => ( is => 'ro', isa => 'HashRef', default => sub { {
#    a => 0, # toggle the anonymous channel flag
#    i => 0, # toggle the invite-only channel flag
#    m => 0, # toggle the moderated channel
#    n => 0, # toggle the no messages to channel from clients on the outside
#    q => 0, # toggle the quiet channel flag
#    p => 0, # toggle the private channel flag
#    s => 0, # toggle the secret channel flag
#    r => 0, # toggle the server reop channel flag
#    t => 0, # toggle the topic settable by channel operator only flag;
#
#    k => '', # set/remove the channel key (password)
#    l => 0,  # set/remove the user limit to channel
#
#    b => '', # set/remove ban mask to keep users out
#    e => '', # set/remove an exception mask to override a ban mask
#    I => '', # set/remove an invitation mask to automatically override the invite-only flag
#} } );

sub new {
    my $class = shift;
    $class->SUPER::new(@_);
}

sub users { # has_many
    local $_;
    my $self = shift;
    my @logins = map { $_->u_login } $self->{teng}->search('channel_user', { c_name => $self->name, @_ });
    $self->{teng}->search('user', { login => \@logins });
}

sub operators { # has_many
    my $self = shift;
    $self->users( operator => 1, @_ );
}

sub speakers { # has_many
    my $self = shift;
    $self->users( speaker => 1, @_ );
}

sub get_users {
    my $self = shift;
    $self->users( u_login => [collect_login(@_)]);
}

sub join_users {
    local $_;
    my $self = shift;
    my $c_name = $self->name;
    my @insert_multi = map { +{ c_name => $c_name, u_login => $_ } } collect_login(@_);
    $self->{teng}->bulk_insert('channel_user', \@insert_multi);
}

sub part_users {
    my $self = shift;
    my @logins = collect_login(@_);
    $self->{teng}->delete('channel_user', +{ c_name => $self->name, u_login => [collect_login(@_)] });
}

sub has_user {
    my ($self, $login) = @_;
    $self->{teng}->single('channel_user', { c_name => $self->name, u_login => $login }) ? 1 : 0;
}

sub login_list {
    local $_;
    my $self = shift;
    map { $_->u_login } $self->{teng}->search('channel_user', { c_name => $self->name, @_ });
}

sub nick_list {
    local $_;
    my $self = shift;
    map { $_->nick } $self->users( @_ );
}

sub user_count {
    my $self = shift;
    my @users = $self->users( @_ );
    scalar @users;
}

sub give_operator {
    my $self = shift;
    $self->{teng}->update_or_create('channel_user', { operator => 1, c_name => $self->name, u_login => [collect_login(@_)] })
}

sub deprive_operator {
    my $self = shift;
    $self->{teng}->update_or_create('channel_user', { operator => 0, c_name => $self->name, u_login => [collect_login(@_)] })
}

sub is_operator {
    my ($self, $login) = @_;
    $self->{teng}->single('channel_user', { operator => 1, c_name => $self->name, u_login => $login }) ? 1 : 0;
}

sub operator_login_list {
    my $self = shift;
    $self->login_list( operator => 1 );
}

sub operator_nick_list {
    my $self = shift;
    $self->nick_list( operator => 1 );
}

sub operator_count {
    my $self = shift;
    $self->user_count( operator => 1 );
}

sub give_voice {
    my $self = shift;
    $self->{teng}->update_or_create('channel_user', { speaker => 1, c_name => $self->name, u_login => [collect_login(@_)] })
}

sub deprive_voice {
    my $self = shift;
    $self->{teng}->update_or_create('channel_user', { speaker => 0, c_name => $self->name, u_login => [collect_login(@_)] })
}

sub is_speaker {
    my ($self, $login) = @_;
    $self->{teng}->single('channel_user', { speaker => 1, c_name => $self->name, u_login => $login }) ? 1 : 0;
}

sub speaker_login_list {
    my $self = shift;
    $self->login_list( speaker => 1 );
}

sub speaker_nick_list {
    my $self = shift;
    $self->nick_list( speaker => 1 );
}

sub speaker_count {
    my $self = shift;
    $self->user_count( speaker => 1 );
}

sub collect_login { local $_; map { ref $_ ? $_->login : $_ } @_; }


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
