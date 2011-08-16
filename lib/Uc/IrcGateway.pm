package Uc::IrcGateway;

use 5.010;
use common::sense;
use warnings qw(utf8);
use version; our $VERSION = qv('0.3.0');

use Any::Moose;
use Any::Moose qw(::Util::TypeConstraints);
use AnyEvent::Socket;
use AnyEvent::IRC::Util qw(parse_irc_msg mk_msg);
use Sys::Hostname;
use Path::Class;
use Uc::IrcGateway::Util::User;
use Uc::IrcGateway::Util::Channel;
use Uc::IrcGateway::Util::Connection;
use Uc::IrcGateway::Util::TypableMap;

#use Smart::Comments;

BEGIN {
    no strict 'refs';
    while (my ($code, $name) = each %AnyEvent::IRC::Util::RFC_NUMCODE_MAP) {
        *{"${name}"} = sub () { $code };
    }
};

extends qw/Object::Event Exporter/;
subtype 'NoBlankedStr' => as 'Str'   => where { /^\S+$/ } => message { "This Str ($_) should not have any blanks!" };
coerce  'NoBlankedStr' => from 'Str' => via { s/\s+//g; $_ };
has 'host' => ( is => 'ro', isa => 'Str', required => 1, default => '127.0.0.1' );
has 'port' => ( is => 'ro', isa => 'Int', required => 1, default => 6667 );
has 'servername'  => ( is => 'rw', isa => 'Str', required => 1, default => sub { hostname() } );
has 'gatewayname' => ( is => 'rw', isa => 'NoBlankedStr', required => 1, default => 'ucircgateway' );
has 'welcome'    => ( is => 'rw', isa => 'Str', default => 'welcome to my irc server' );
has 'ctime'      => ( is => 'ro', isa => 'Str', lazy => 1, builder => sub { scalar localtime } );
has 'admin'      => ( is => 'ro', isa => 'Str', default => 'nobody' );
has 'password'   => ( is => 'ro', isa => 'NoBlankedStr');
has 'motd' => ( is => 'ro', isa => 'Path::Class::File', default => sub { (my $file = $0) =~ s/\.\w+$//; file("$file.motd.txt") } );
has 'channel_name_prefix' => ( is => 'ro', isa => 'NoBlankedStr', default => '#' );
has 'daemon' => ( is => 'ro', isa => 'Uc::IrcGateway::Util::User', lazy => 1, builder => sub {
    my $self = shift;
    my $gatewayname = $self->gatewayname;
    Uc::IrcGateway::Util::User->new(
        nick => $gatewayname, login => $gatewayname, realname => $self->admin,
        host => $self->host, addr => $self->host, server => $self->host,
    );
});

our %IRC_COMMAND_EVENT = ();
our @IRC_COMMAND_LIST = qw(
    pass nick user oper quit
    join part mode invite kick
    topic privmsg notice away
    names list who whois whowas users userhost ison

    server squit
    version stat link time admin info
    connect trace
    kill rehash restart summon wallops
    ping pong error
);
our @IRC_COMMAND_LIST_OK = qw(
    nick user
    join part
    topic privmsg notice
    names list who whois
    ping pong
);

{
    local $_;
    no strict 'refs';
    for (@IRC_COMMAND_LIST) {
        given ($_) {
            when (\@IRC_COMMAND_LIST_OK) { $IRC_COMMAND_EVENT{$_} = \&{"_event_$_"} }
            default { $IRC_COMMAND_EVENT{$_} = \&_event; }
        }
    }
}

our $CRLF = "\015\012";
our @EXPORT = qw(parse_irc_msg mk_msg _check_params);
push @EXPORT, values %AnyEvent::IRC::Util::RFC_NUMCODE_MAP;

__PACKAGE__->meta->make_immutable;
no Any::Moose;

sub BUILD {}
sub run {
    my $self = shift;
    $self->ctime;
    tcp_server $self->host, $self->port, sub {
        my ($fh, $host, $port) = @_;
        my $handle = Uc::IrcGateway::Util::Connection->new(fh => $fh,
            on_error => sub {
                my $handle = shift;
                $self->event('on_error', $handle);
            },
            on_eof => sub {
                my $handle = shift;
                $self->event('on_eof', $handle);
            },
        );
        $handle->on_read(sub { $handle->push_read(line => sub {
            my ($handle, $line, $eol) = @_;
            ### $line
            my $msg = parse_irc_msg($line);
            ### $msg
            $self->handle_msg($msg, $handle);
        }) });
    }, sub {
        my ($fh, $host, $port) = @_;
        say "bound to $host:$port";
        say $self->welcome();
    };
}

sub _check_params {
    my ($self, $msg, $handle) = @_;
    my $cmd   = $msg->{command};
    my $param = $msg->{params}[0];

    unless ($param) {
        $self->need_more_params($handle, $cmd);
        return ();
    }

    @_;
}

sub _event {
    my ($self, $msg, $handle) = @_;
    my $cmd  = $msg->{command};

    # <command> is not implemented
    $self->send_msg( $handle, ERR_UNKNOWNCOMMAND, $cmd, "is not implemented" );

    @_;
}

sub _event_nick {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my $cmd  = $msg->{command};
    my $nick = $msg->{params}[0];
    my $user = $handle->self;
    if (defined $user) {
        $self->send_cmd( $handle, $user, $cmd, $nick );
        $user->nick($nick);
    }
    else {
        $handle->self(Uc::IrcGateway::Util::User->new(
            nick => $nick, login => '*', realname => '*',
            host => '*', addr => '*', server => '*',
        ));
    }

    @_;
}

sub _event_user {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my ($login, $host, $server, $realname) = @{$msg->{params}};
    my $user = $handle->self;
    return unless $self;

    $host ||= '0'; $server ||= '*'; $realname ||= '';
    $user->login($login);
    $user->realname($realname);
    $user->host($host);
    $user->addr($self->host);
    $user->server($server);

    $self->send_msg( $handle, RPL_WELCOME, $self->welcome );
    $self->send_msg( $handle, RPL_YOURHOST, "Your host is @{[ $self->servername ]} [@{[ $self->servername ]}/@{[ $self->port ]}]. @{[ ref $self ]}/$VERSION" );
    $self->send_msg( $handle, RPL_CREATED, "This server was created ".$self->ctime );
    $self->send_msg( $handle, RPL_MYINFO, "@{[ $self->servername ]} @{[ ref $self ]}-$VERSION" );
    if (-e $self->motd) {
        my $fh = $self->motd->open('r', ':raw');
        if (defined $fh) {
            my $i = 0;
            while (<$fh>) {
                chomp $_;
                $self->send_msg( $handle, (!$i++ ? RPL_MOTDSTART : RPL_MOTD), $_ );
            }
        }
        $self->send_msg( $handle, RPL_ENDOFMOTD, "End of /MOTD command" );
    }
    else {
        $self->send_msg( $handle, ERR_NOMOTD, "MOTD File is missing" );
    }

    @_;
}

sub _event_join {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my $chans = $msg->{params}[0];
    my $nick = $handle->self->nick;

    for my $chan (split /,/, $chans) {
        next unless $self->check_channel_name( $handle, $chan );

        $handle->set_channels($chan => Uc::IrcGateway::Util::Channel->new) if !$handle->has_channel($chan);
        $handle->get_channels($chan)->set_users( $nick => $handle->self );

        # send join message
        $self->send_cmd( $handle, $handle->self, 'JOIN', $chan );

        # sever reply
        $self->send_msg( $handle, RPL_TOPIC, $chan, $handle->get_channels($chan)->topic || '' );
        $self->handle_msg( parse_irc_msg("WHO $chan"), $handle );
        $self->send_cmd( $handle, $self->daemon, 'MODE', $chan, '+o', $nick );
    }

    @_;
}

sub _event_part {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my ($chans, $text) = @{$msg->{params}};
    my $nick = $handle->self->nick;

    for my $chan (split /,/, $chans) {
        next unless $self->check_channel_name( $handle, $chan, joined => 1 );

        $handle->get_channels($chan)->del_users($nick);

        # send part message
        $self->send_cmd( $handle, $handle->self, 'PART', $chan, $text );
    }

    @_;
}

sub _event_topic {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my ($chan, $topic) = @{$msg->{params}};
    return () unless $self->check_channel_name( $handle, $chan, enable => 1 );

    if ($topic) {
        $handle->get_channels($chan)->topic( $topic );
        $self->send_msg( $handle, RPL_TOPIC, $chan, $topic );
    }
    else {
        $self->send_msg( $handle, RPL_NOTOPIC, $chan, 'No topic is set' );
    }

    @_;
}

sub _event_privmsg {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my ($chan, $text) = @{$msg->{params}};
    return () unless $self->check_channel_name( $handle, $chan, enable => 1 );

    # echo
    $self->send_cmd( $handle, $handle->self, 'NOTICE', $chan, $text );

    @_;
}

sub _event_notice {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my ($chan, $topic) = @{$msg->{params}};

    # no reply is sent

    @_;
}

sub _event_ping {}
sub _event_pong {}

sub _event_names {
    my ($self, $msg, $handle) = @_;
    my $chans = $msg->{params}[0] || join ',', sort $handle->channel_list;

    for my $chan (split /,/, $chans) {
        next unless $self->check_channel_name( $handle, $chan, enable => 1 );
        my $c = $handle->get_channels($chan);
#        my @names;
#        for my $name ($c->user_list) {
#            my $m = $c->get_users($name)->mode;
#            push @names, ($m->{o} ? '@' : $m->{m} ? '+' : '') . $name;
#        }
#        $self->send_msg( $handle, RPL_NAMREPLY, $chan, ':'.join ',', @names );
        $self->send_msg( $handle, $self->daemon, RPL_NAMREPLY, '@', $chan, join ' ', sort $c->user_list );
        $self->send_msg( $handle, $self->daemon, RPL_ENDOFNAMES, '@', $chan, 'End of /NAMES list' );
    }

    @_;
}

sub _event_list {
    my ($self, $msg, $handle) = @_;
    my $chans = $msg->{params}[0] || join ',', sort $handle->channel_list;
    my $nick = $handle->self->nick;

    $self->send_msg( $handle, RPL_LISTSTART, $nick, 'Channel', 'Users Name' );
    for my $chan (split /,/, $chans) {
        next unless $self->check_channel_name( $handle, $chan, enable => 1 );
        my $channel = $handle->get_channels($chan);
        my $member_count = scalar values %{$channel->users};
        my $topic = $channel->topic;
        $self->send_msg( $handle, RPL_LIST, $chan, $member_count, $topic );
    }
    $self->send_msg( $handle, RPL_LISTEND, 'END of /List' );

    @_;
}

sub _event_who {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my ($check, $oper) = @{$msg->{params}};
    return () unless $self->check_channel_name( $handle, $check, enable => 1 );

    # TODO: いまのところ channel の完全一致チェックしにか対応してません
    for my $u (values %{$handle->get_channels($check)->users}) {
        $self->send_msg( $handle, RPL_WHOREPLY, $check, $u->login, $u->host, $u->server, $u->nick, 'H', '1 '.$u->realname);
    }
    $self->send_msg( $handle, RPL_ENDOFWHO, $check, 'END of /WHO List');

    @_;
}

sub _event_whois {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my $nicks = $msg->{params}[0];
    my %all_users = $handle->all_users;

    for my $nick (split /,/, $nicks) {
        my $user = $all_users{$nick};

        $self->send_msg( $handle, RPL_AWAY, $nick, $user->away_message ) if $user->away_message;
        $self->send_msg( $handle, RPL_WHOISUSER, $nick, $user->login, $user->host, '*', $user->realname );
        $self->send_msg( $handle, RPL_WHOISSERVER, $nick, $user->server, $user->server );
        $self->send_msg( $handle, RPL_WHOISOPERATOR, $nick, 'is an IRC operator' );
        $self->send_msg( $handle, RPL_WHOISIDLE, $nick, time - $user->last_modified, 'seconds idle' );
        $self->send_msg( $handle, RPL_WHOISCHANNELS, $nick, join ' ', $handle->who_is_channel($nick) );
        $self->send_msg( $handle, RPL_ENDOFWHOIS, $nick, 'End of /WHOIS list' );
    }
}

sub handle_msg {
    my ($self, $msg, $handle) = @_;
    my $event = lc($msg->{command});
       $event =~ s/^(\d+)$/irc_$1/g;
    $self->event($event, $msg, $handle);
}

sub server_comment {
    my ($self, $nick, $login) = @_;
    $login = $nick if $login eq '';
    return sprintf '%s!~%s@%s', $nick, $nick, $self->servername;
}

sub send_msg {
    my ($self, $handle, $cmd, @args) = @_;
    my $msg = mk_msg($self->daemon->to_prefix, $cmd, $handle->self->nick, @args) . $CRLF;
    ### $msg
    $handle->push_write($msg);
}

sub send_cmd {
    my ($self, $handle, $user, $cmd, @args) = @_;
    my $prefix = ref $user eq 'Uc::IrcGateway::Util::User' ? $user->to_prefix : $user;
    my $msg = mk_msg($prefix, $cmd, @args) . $CRLF;
    ### $msg
    $handle->push_write($msg);
}

sub need_more_params {
    my ($self, $handle, $cmd) = @_;
    $self->send_msg($handle, ERR_NEEDMOREPARAMS, $cmd, 'Not enough parameters');
}

sub valid_channel_name {
    my ($self, $chan) = @_;
    my $match = $self->channel_name_prefix . '[^\s,]+';
    return $chan =~ /^$match$/;
}

sub check_channel_name {
    my ($self, $handle, $chan, %opt) = @_;
    if (not $self->valid_channel_name($chan)) {
        $self->send_msg( $handle, ERR_NOSUCHCHANNEL, $chan, 'Invalid channel name' ) unless $opt{silent};
        return 0;
    }
    if (($opt{enable} || $opt{joined}) && !$handle->has_channel($chan)) {
        $self->send_msg( $handle, ERR_NOSUCHCHANNEL, $chan, 'No such channel' ) unless $opt{silent};
        return 0;
    }
    if ($opt{joined} && !$handle->get_channels($chan)->has_user($handle->self->nick)) {
        $self->send_msg( $handle, ERR_NOTONCHANNEL, $chan, "You're not on that channel" ) unless $opt{silent};
        return 0;
    }
    return 1;
}


1; # Magic true value required at end of module
__END__

=head1 NAME

Uc::IrcGateway - [One line description of module's purpose here]


=head1 VERSION

This document describes Uc::IrcGateway version 0.1.1


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
  
Uc::IrcGateway requires no configuration files or environment variables.


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
