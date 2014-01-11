package Uc::IrcGateway::Connection;

use 5.014;
use warnings;
use utf8;

use parent qw(AnyEvent::Handle);

use Uc::IrcGateway::Common;
use Uc::IrcGateway::Structure;

use Carp ();
use Path::Class qw(file);
use Scalar::Util qw(refaddr blessed);

use Class::Accessor::Lite (
    rw => [qw(self)],
    ro => [ qw(
        ircd
        schema

        options
        users
        channels
    )],
);

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;

    my $self = $class->SUPER::new(
        self => undef,
        ircd => undef,
        schema => Uc::IrcGateway::Structure->new( dbh => setup_dbh() ),

        options => +{},
        users => +{},
        channels => +{},

        registered => 0,

        %args,
    );

    $self->schema->setup_database;

    $self;
}

sub set_user {
    my $self = shift;
    my %args = @_ != 1 ? @_ : blessed $_[0] && $_[0]->isa('Uc::IrcGateway::TempUser')
                            ? %{$_[0]->user_prop} : %{$_[0]};
    $self->schema->insert('user', \%args);
}

sub get_users {
    my $self = shift;
    my $login = @_ == 1 ? shift : \@_;
    my $method = ref $login ? 'search' : 'single';
    $self->schema->$method('user', +{ login => $login });
}

sub get_users_by_nicks {
    my $self = shift;
    my $nick = @_ == 1 ? shift : \@_;
    my $method = ref $nick ? 'search' : 'single';
    $self->schema->$method('user', +{ nick => $nick });
}

sub del_users {
    my $self = shift;
    my $login = @_ == 1 ? shift : \@_;
    $self->schema->delete('user', +{ login => $login });
}

sub has_user {
    my ($self, $login) = @_;
    $self->schema->single('user', +{ login => $login }) ? 1 : 0;
}

sub has_nick {
    my ($self, $nick) = @_;
    $self->schema->single('user', +{ nick => $nick }) ? 1 : 0;
}

sub lookup {
    my ($self, $nick) = @_;
    my $user = $self->schema->single('user', +{ nick => $nick });
    $user ? $user->login : undef;
}

sub user_list {
    local $_;
    my $self = shift;
    map { $_->login } $self->schema->search('user');
}

sub nick_list {
    local $_;
    my $self = shift;
    map { $_->nick } $self->schema->search('user');
}

sub set_channels {
    local $_;
    my $self = shift;
    my @insert_multi = map { +{ name => $_ } } @_;
    $self->schema->bulk_insert('channel', \@insert_multi);
}

my %CHANNEL_CACHE;
sub get_channels {
    local $_;
    my $self = shift;
    my $method = wantarray ? 'search' : 'single';
    my @cache;
    my @names = map {
        if (exists $CHANNEL_CACHE{$_}) { push @cache, $CHANNEL_CACHE{$_}; (); }
        else                           { ($_); }
    } @_;
    my @result = $self->schema->$method('channel', +{ name => \@names });
    return @cache if scalar @result && defined $result[0];
    map { $CHANNEL_CACHE{$_->name} = $_ } @result;
    return (@cache, @result);
}

sub del_chnnels {
    my $self = shift;
    map { delete $CHANNEL_CACHE{$_} } @_;
    $self->schema->delete('channel', +{ name => \@_ });
}

sub has_channel {
    my ($self, $c_name) = @_;
    return 1 if exists $CHANNEL_CACHE{$c_name};
    $self->schema->single('channel', +{ name => $c_name }) ? 1 : 0;
}

sub channel_list {
    local $_;
    my $self = shift;
    map { $_->name } $self->schema->search('channel');
}

sub who_is_channels {
    local $_;
    my ($self, $login) = @_;
    map { $_->c_name } $self->schema->search('channel_user', +{ u_login => $login });
}

sub get_state {
    my ($self, $key) = @_;
    my $state = $self->schema->single('state', +{ key => $key });
    $state ? Uc::IrcGateway::Common::from_json($state->value) : ();
}

sub set_state {
    my ($self, $key, $value) = @_;
    $self->schema->update_or_create('state', +{ key => $key, value => Uc::IrcGateway::Common::to_json($value, pretty => 0) });
}


1; # Magic true value required at end of module
__END__

=encoding utf-8

=head1 NAME

Uc::IrcGateway::Connection - Uc::IrcGatewayのためのコネクションクラス


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
