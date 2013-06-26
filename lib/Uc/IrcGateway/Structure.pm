package Uc::IrcGateway::Structure;
use 5.014;
use Uc::IrcGateway::Common;
use parent qw(Teng Exporter);
__PACKAGE__->load_plugin('DBIC::ResultSet');

use Carp qw(croak);
use DBI qw(:sql_types);
use DBD::SQLite 1.027;

our @EXPORT = qw(setup_dbh);

sub setup_dbh {
    my $file = shift // ':memory:';
    my $dbh = DBI->connect('dbi:SQLite:'.$file,,,{RaiseError => 1, PrintError => 0, AutoCommit => 1, sqlite_unicode => 1});
    $dbh->{sqlite_unicode} = 1;
    $dbh;
}

our %CREATE_TABLE_SQL = (
    state            => q{
CREATE TABLE 'state' (
  'key'  text NOT NULL,
  'value' text,

  PRIMARY KEY ('key')
)
    },
    channel          => q{
CREATE TABLE 'channel' (
  'name'          text    NOT NULL,
  'topic'         text,

  'password'      text    NOT NULL DEFAULT '',
  'user_limit'    int     NOT NULL DEFAULT 0,

  'ban_mask'      text    NOT NULL DEFAULT '',
  'ex_ban_mask'   text    NOT NULL DEFAULT '',
  'invite_mask'   text    NOT NULL DEFAULT '',

  'anonymous'     boolean NOT NULL DEFAULT 0,
  'invite_only'   boolean NOT NULL DEFAULT 0,
  'moderate'      boolean NOT NULL DEFAULT 0,
  'no_message'    boolean NOT NULL DEFAULT 0,
  'quiet'         boolean NOT NULL DEFAULT 0,
  'private'       boolean NOT NULL DEFAULT 0,
  'secret'        boolean NOT NULL DEFAULT 0,
  'reop'          boolean NOT NULL DEFAULT 0,
  'op_topic_only' boolean NOT NULL DEFAULT 0,

  PRIMARY KEY ('name')
)
    },
    user             => q{
CREATE TABLE 'user' (
  'login'          text NOT NULL,
  'nick'           text NOT NULL,
  'password'       text NOT NULL DEFAULT '',
  'realname'       text NOT NULL DEFAULT '',
  'host'           text NOT NULL DEFAULT 'localhost',
  'addr'           text NOT NULL DEFAULT '',
  'server'         text NOT NULL DEFAULT '',

  'userinfo'       text,
  'away_message'   text,
  'last_modified'  int,

  'away'           boolean NOT NULL DEFAULT 0,
  'invisible'      boolean NOT NULL DEFAULT 0,
  'allow_wallops'  boolean NOT NULL DEFAULT 0,
  'restricted'     boolean NOT NULL DEFAULT 0,
  'operator'       boolean NOT NULL DEFAULT 0,
  'local_operator' boolean NOT NULL DEFAULT 0,
  'allow_s_notice' boolean NOT NULL DEFAULT 0,

  PRIMARY KEY ('login', 'nick')
)
    },
    channel_user     => q{
CREATE TABLE 'channel_user' (
  'c_name'   text    NOT NULL,
  'u_login'  text    NOT NULL,
  'operator' boolean NOT NULL DEFAULT 0,
  'speaker'  boolean NOT NULL DEFAULT 0,

  PRIMARY KEY ('c_name', 'u_login')
)
    },
);

sub setup_database {
    my ($self, %opt) = @_;
    my %sql = %CREATE_TABLE_SQL;
    my $dbh = $self->dbh;

    $self->drop_table if $opt{force_create_table};

    for my $table (keys %sql) {
        my $sth = $dbh->prepare(q{
            SELECT count(*) FROM sqlite_master
                WHERE type='table' AND name=?;
        });
        $sth->execute($table);
        delete $sql{$table} if $sth->fetchrow_arrayref->[0];
    }

    $self->execute($sql{$_}) for keys %sql;
}

sub drop_table {
    my $self = shift;
    $self->execute("DROP TABLE IF EXISTS $_") for scalar @_ ? @_ : keys %CREATE_TABLE_SQL;
}


package Uc::IrcGateway::Structure::Schema;

use 5.014;
use warnings;
use utf8;
use Teng::Schema::Declare;

use DBI qw(:sql_types);

table {
    name "state";
    pk qw( key );
    columns (
        { name => "key",   type => SQL_VARCHAR },
        { name => "value", type => SQL_VARCHAR },
    );
};

table {
    name "channel";
    pk qw( name );
    columns (
        { name => "name",          type => SQL_VARCHAR },
        { name => "topic",         type => SQL_VARCHAR },
        { name => "password",      type => SQL_VARCHAR },
        { name => "user_limit",    type => SQL_INTEGER },
        { name => "ban_mask",      type => SQL_VARCHAR },
        { name => "ex_ban_mask",   type => SQL_VARCHAR },
        { name => "invite_mask",   type => SQL_VARCHAR },
        { name => "anonymous",     type => SQL_BOOLEAN },
        { name => "invite_only",   type => SQL_BOOLEAN },
        { name => "moderate",      type => SQL_BOOLEAN },
        { name => "no_message",    type => SQL_BOOLEAN },
        { name => "quiet",         type => SQL_BOOLEAN },
        { name => "private",       type => SQL_BOOLEAN },
        { name => "secret",        type => SQL_BOOLEAN },
        { name => "reop",          type => SQL_BOOLEAN },
        { name => "op_topic_only", type => SQL_BOOLEAN },
    );
    row_class "Uc::IrcGateway::Channel";
};

table {
    name "user";
    pk qw( login nick );
    columns (
        { name => "login",          type => SQL_VARCHAR },
        { name => "nick",           type => SQL_VARCHAR },
        { name => "realname",       type => SQL_VARCHAR },
        { name => "host",           type => SQL_VARCHAR },
        { name => "addr",           type => SQL_VARCHAR },
        { name => "server",         type => SQL_VARCHAR },
        { name => "userinfo",       type => SQL_VARCHAR },
        { name => "away_message",   type => SQL_VARCHAR },
        { name => "last_modified",  type => SQL_INTEGER },
        { name => "away",           type => SQL_BOOLEAN },
        { name => "invisible",      type => SQL_BOOLEAN },
        { name => "allow_wallops",  type => SQL_BOOLEAN },
        { name => "restricted",     type => SQL_BOOLEAN },
        { name => "operator",       type => SQL_BOOLEAN },
        { name => "local_operator", type => SQL_BOOLEAN },
        { name => "allow_s_notice", type => SQL_BOOLEAN },
    );
    row_class "Uc::IrcGateway::User";
};

table {
    name "channel_user";
    pk qw( c_name u_login );
    columns (
        { name => "c_name",   type => SQL_VARCHAR },
        { name => "u_login",  type => SQL_VARCHAR },
        { name => "operator", type => SQL_BOOLEAN },
        { name => "speaker",  type => SQL_BOOLEAN },
    );
};


package Uc::IrcGateway::Structure::Row::ChannelUser;
use parent 'Teng::Row';

sub channel { # blongs_to
    my $self = shift;
    $self->{teng}->single('channel', { name => $self->c_name, @_ });
}

sub users { # has_many
    my $self = shift;
    $self->{teng}->search('user', { login => $self->u_login, @_ });
}

sub user { # blongs_to
    my $self = shift;
    $self->{teng}->single('user', { login => $self->u_login, @_ });
}


1; # Magic true value required at end of module
__END__

=head1 NAME

Uc::IrcGateway::Structure - Uc::IrcGatewayのための永続的な状態を扱うための構造体クラス


=head1 SYNOPSIS

    use Uc::IrcGateway::Connection;
    my $handle = Uc::IrcGateway::Connection->new( fh => $fh );

    # you should set 'self' before call 'schema'

    $handle->self();

    # get Uc::IG data structure
    my $schema = $handle->schema();

    # get connection user's information
    my $user_info = $schema->single('user', { nick => $handle->self->nick });
    $user_info->nick # connection user's nick name

    # or

    my $user = $handle->get_user( nick => $handle->self->nick );
    $user->nick;



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
