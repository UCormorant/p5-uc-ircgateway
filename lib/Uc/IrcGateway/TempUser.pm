package Uc::IrcGateway::TempUser;

use 5.014;
use warnings;
use utf8;

use Carp qw(croak);
use Path::Class qw(file);
use Uc::IrcGateway::Structure;
use AnyEvent;

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
use Class::Accessor::Lite rw => [@USER_PROP, 'registered'];

# constructer

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;

    $args{registered} //= 0;

    bless +{
        %args,
    }, $class;
}

# other method

sub register {
    my ($self, $handle) = @_;

    croak "user registration error: nick is not defined"  if not $self->nick;
    croak "user registration error: login is not defined" if not $self->login;

    my $db = file($handle->ircd->app_dir, sprintf "%s.sqlite", $self->login);
    my $exists_db = -e $db;
    if ($handle->options->{in_memory}) {
        $handle->schema->{dbh}->sqlite_backup_from_file($db) if $exists_db;
        # backup timer
        $handle->{_guard_backup_db} = AnyEvent->timer(after => 1*60, interval => 1*60, cb => sub{
            $handle->ircd->log($handle, debug => 'database backup');
            $handle->schema->{dbh}->sqlite_backup_to_file($db);
        });
    }
    else {
        $handle->schema->{dbh} = setup_dbh($db);
        $handle->schema->setup_database if not $exists_db;
    }

    my $user;
    if ($user = $handle->get_users($self->login)) {
        $user->update($self->user_prop);
    }
    else {
        $user = $handle->set_user($self->user_prop);
    }
    $handle->self($user);
    $handle->self->part_from_all_channels;

    $user;
}

sub to_prefix {
    my $self = shift;
    sprintf "%s!%s@%s", $self->registered ? (@{$self}{qw/nick login host/}) : ("*", "*", "*");
}

sub user_prop {
    +{ map { defined $_[0]{$_} ? ($_ => $_[0]{$_}) : () } @USER_PROP };
}

sub mode_string {
    join '', map { $_[0]->{$_} ? $MODE_TABLE{$_} : () } sort keys @{$_[0]}{keys %MODE_TABLE};
}


1; # Magic true value required at end of module
__END__

=encoding utf-8

=head1 NAME

Uc::IrcGateway::TempUser - Temporary User Object for Uc::IrcGateway


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
