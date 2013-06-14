package Uc::IrcGateway v3.0.0;

use 5.014;
use warnings;
use utf8;

use parent qw(Object::Event);

use Uc::IrcGateway::Connection;
use Uc::IrcGateway::User;

use AnyEvent::Socket qw(tcp_server);
use AnyEvent::IRC::Util qw(
    mk_msg parse_irc_msg split_prefix decode_ctcp encode_ctcp
    prefix_nick prefix_user prefix_host is_nick_prefix join_prefix
);
use DBD::SQLite 1.027;
use Carp qw(croak);
use Encode qw(find_encoding);
use Path::Class qw(file);
use Sys::Hostname qw(hostname);
use Scalar::Util qw(refaddr);
use IO::Socket::INET ();
use UNIVERSAL::which ();
use YAML::XS ();
use JSON::XS ();

use Class::Accessor::Lite (
    rw => [ qw(
        host
        port
        time_zone
        servername
        gatewayname
        daemon
        motd
        ping_timeout
        debug
    )],
    ro => [ qw(
        handles
        ctime
    )],
);

BEGIN {
    no strict 'refs';
    while (my ($code, $name) = each %AnyEvent::IRC::Util::RFC_NUMCODE_MAP) {
        *{$name} = sub () { $code };
    }
}

our $MAXBYTE  = 512;
our $NUL      = "\0";
our $BELL     = "\07";
our $CRLF     = "\015\012";
our $SPECIAL  = '\[\]\\\`\_\^\{\|\}';
our $SPCRLFCL = " $CRLF:";
our %REGEX = (
    crlf     => qr{\015*\012},
    chomp    => qr{[$CRLF$NUL]+$},
    channel  => qr{^(?:[#+&]|![A-Z0-9]{5})[^$SPCRLFCL,$BELL]+(?:\:[^$SPCRLFCL,$BELL]+)?$},
    nickname => qr{^[\w][-\w$SPECIAL]*$}, # 文字数制限,先頭の数字禁止は扱いづらいのでしません
);
our %IRC_COMMAND_EVENT = ();
our @IRC_COMMAND_LIST_ALL = qw(
    pass nick user oper quit
    join part mode invite kick
    topic privmsg notice away
    names list who whois whowas
    users userhost ison

    service squery

    server squit wallops
    motd version time admin info
    lusers stats links servlist
    connect trace
    kill rehash die restart summon wallops

    ping pong error
);
our @IRC_COMMAND_LIST = qw(
    nick user quit
    join part mode invite
    topic privmsg notice away
    names list who whois
    ison

    motd

    ping pong
);

our %CTCP_COMMAND_EVENT = ();
our @CTCP_COMMAND_LIST_ALL = qw(
    finger userinfo time
    version source
    clientinfo errmsg ping
    action dcc sed
);
our @CTCP_COMMAND_LIST = qw(
    userinfo
    clientinfo
    action
);
our %CTCP_COMMAND_INFO = (
    clientinfo => 'CLIENTINFO with 0 arguments gives a list of known client query keywords. With 1 argument, a description of the client query keyword is returned.',
);

our @EXPORT = qw(
    check_params is_valid_channel_name
    opt_parser decorate_text replace_crlf

    mk_msg parse_irc_msg split_prefix decode_ctcp encode_ctcp
    prefix_nick prefix_user prefix_host is_nick_prefix join_prefix
);
push @EXPORT, values %AnyEvent::IRC::Util::RFC_NUMCODE_MAP;


sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;

    my $self = bless +{
        debug => 0,

        host => '127.0.0.1',
        port => 6667,
        time_zone => 'local',
        servername => scalar hostname(),
        gatewayname => '*ucircgd',
        motd => file($0 =~ s/(.*)\.\w+$/$1.motd.txt/r),
        ping_timeout => 30,

        charset     => 'utf8',
        err_charset => ($^O eq 'MSWin32' ? 'cp932' : 'utf8'),

        handles => {},

        %args,
    }, $class;

    $self->daemon(Uc::IrcGateway::User->new(nick => $self->gatewayname));
    $self->{codec}     = find_encoding($self->charset);
    $self->{err_codec} = find_encoding($self->err_charset);

    $self;
}

sub run {
    my $self = shift;

    say "Starting irc gateway server on @{[ $self->host.':'.$self->port ]}";

    print "Check port... ";
    IO::Socket::INET->new(
        Proto => "tcp",
        PeerAddr => $self->host,
        PeerPort => $self->port,
        Timeout => "1",
    ) and croak "stop. @{[ $self->host.':'.$self->port ]} is already used by other process";

    # TODO: ポートを開けないアドレスのチェック
    my $check = IO::Socket::INET->new(
        Proto => "tcp",
        LocalAddr => $self->host,
        LocalPort => $self->port,
        Listen => 1,
    ) or croak "stop. $!";
    $check->listen or croak "stop. cannot listen on @{[ $self->host.':'.$self->port ]}";
    $check->close;
    say "done.";

    tcp_server $self->host, $self->port, sub {
        my ($fh, $host, $port) = @_;
        my $handle = Uc::IrcGateway::Connection->new(fh => $fh,
            on_error => sub {
                my ($handle, $fatal, $message) = @_;
                $self->event('on_error', $handle, $fatal, $message);
                delete $self->handles->{refaddr($handle)} if $fatal;
            },
            on_eof => sub {
                my $handle = shift;
                $self->event('on_eof', $handle);
                delete $self->handles->{refaddr($handle)};
            },
        );
        $handle->on_read(sub {
            # \015* for some broken servers, which might have an extra
            # carriage return in their MOTD.
            $_[0]->push_read(line => $REGEX{crlf}, sub {
                my ($handle, $line, $eol) = @_;
                $line =~ s/$REGEX{chomp}//g;
                $self->handle_irc_msg($handle, $self->codec->decode($line));
            });
        });
        $self->handles->{refaddr($handle)} = $handle;
    }, sub {
        my ($fh, $host, $port) = @_;
        $self->{ctime} = scalar localtime;

        say "Bound to $host:$port";

        print "Mapping event... "; print "\n" if $self->debug;
        my ($irc_method, $ctcp_method) = ('_event_irc', '_event_ctcp');
        $IRC_COMMAND_EVENT{irc} = $self->can($irc_method);
        $CTCP_COMMAND_EVENT{ctcp} = $self->can($ctcp_method);

        for my $cmd (@IRC_COMMAND_LIST) {
            my $method = $irc_method; $method .= "_$cmd" if $self->can($method."_$cmd");
            say "    irc_cmd: ".uc("$cmd => ").scalar $self->which($method) if $self->debug;
            $IRC_COMMAND_EVENT{"irc_$cmd"} = $self->can($method);
        }
        for my $cmd (@CTCP_COMMAND_LIST) {
            my $method = $ctcp_method; $method .= "_$cmd" if $self->can($method."_$cmd");
            say "    ctcp_cmd: ".uc("$cmd => ").scalar $self->which($method) if $self->debug;
            $CTCP_COMMAND_EVENT{"ctcp_$cmd"} = $self->can($method);
        }

        $self->reg_cb(
            %IRC_COMMAND_EVENT, %CTCP_COMMAND_EVENT,

            on_eof => sub {
                my ($self, $handle) = @_;
            },
            on_error => sub {
                my ($self, $handle, $fatal, $message) = @_;
                warn "[$fatal] $message";
            },
        );
        say "done.";

        say "Starting '@{[ $self->servername ]}' is succeed.";
        say "@{[ $self->servername ]} settings:";
        say "   - Listen on @{[ $self->host.':'.$self->port ]}";
        say "   - Server created at @{[ $self->ctime ]}";
        say "   - Server time zone is @{[ $self->time_zone ]}";
        say "   - Gateway bot is @{[ $self->gatewayname ]}";
#        say "   - Setting files are in @{[ $self->set_dir ]}";
        say "   - Message Of The Day uses @{[ scalar $self->motd ]}";
    };
}


# event function ( irc command ) #

sub _event_irc {
    my ($self, $handle, $msg) = @_;
    my $cmd = $msg->{command};

    if (not $handle->registered) {
        # You have not registered
        $self->send_msg( $handle, ERR_NOTREGISTERED, "You have not registered" );
    }
    else {
        # <command> is not implemented
        $self->send_msg( $handle, ERR_UNKNOWNCOMMAND, $cmd, "is not implemented" );
    }

    @_;
}


# event function ( ctcp command ) #

sub _event_ctcp {
    my ($self, $handle, $msg, $reply) = @_;

    if (not $handle->registered) {
        # You have not registered
        $self->send_msg( $handle, ERR_NOTREGISTERED, "You have not registered" );
    }
    else {
        # <query> is unknown
        $self->send_ctcp_reply( $handle, $self->daemon, 'ERROR', $msg->{raw}, ':Query is unknown' );
    }

    @_;
}


# IrcGateway method #

# accessor

## read write
sub charset {
    return $_[0]->{charset} if not defined $_[1];
    $_[0]->{charset} = $_[1];
    $_[0]->{codec}   = find_encoding($_[1]);
}

sub err_charset {
    return $_[0]->{err_charset} if not defined $_[1];
    $_[0]->{err_charset} = $_[1];
    $_[0]->{err_codec}   = find_encoding($_[1]);
}

## read only
sub codec {
    $_[0]->{codec};
}

sub err_codec {
    $_[0]->{err_codec};
}

## alias
sub to_prefix {
    $_[0]->host;
}


# client to server
sub handle_irc_msg {
    my ($self, $handle, $raw, %opts) = @_;
    my $msg   = parse_irc_msg($raw);
    my $event = lc($msg->{command} || '');
       $event = exists $IRC_COMMAND_EVENT{"irc_$event"} ? "irc_$event" : 'irc';

#    $self->logger->debug("handle_irc_msg: $raw, ".Dumper(\%opts));
    $msg->{raw} = $raw;
    $msg->{$_}  = $opts{$_} for keys %opts;
    $self->event($event, $handle => $msg);
}

sub handle_ctcp_msg {
    my ($self, $handle, $raw, %opts) = @_;
    my ($msg, $event) = {};

    @{$msg}{qw/command params/} = split(' ', $raw, 2);
    $msg->{params} = [$msg->{params}];
    $event = lc($msg->{command});
    $event = exists $CTCP_COMMAND_EVENT{"ctcp_$event"} ? "ctcp_$event" : 'ctcp';

#    $self->logger->debug("handle_ctcp_msg: $raw, ".Dumper(\%opts));
    $msg->{raw} = $raw;
    $msg->{$_}  = $opts{$_} for keys %opts;
    $self->event($event, $handle => $msg);
}

# server to client
sub send_msg {
    my ($self, $handle, $cmd, @args) = @_;
    $self->send_cmd($handle, $self->to_prefix, $cmd, $handle->self->nick, @args);
}

sub send_cmd {
    my ($self, $handle, $user, $cmd, @args) = @_;
    if (ref $handle and $handle->isa('Uc::IrcGateway::Connection')) {
        my $prefix = ref $user && $user->isa('Uc::IrcGateway::User') ? $user->to_prefix : $user;
        my $msg = mk_msg($prefix, $cmd, @args);
#        $self->logger->debug("send_cmd: $msg");
        $handle->push_write($self->codec->encode($msg) . $CRLF);
    }
    else {
        say "send_cmd: $cmd: ", join ", ", @args;
    }
}

sub send_ctcp_query {
    my ($self, $handle, $user, $cmd, @args) = @_;
    $self->send_cmd( $handle, $user, 'PRIVMSG', $handle->self->nick, encode_ctcp([uc($cmd), @args]) );
}

sub send_ctcp_reply {
    my ($self, $handle, $user, $cmd, @args) = @_;
    $self->send_cmd( $handle, $user, 'NOTICE', $handle->self->nick, encode_ctcp([uc($cmd), @args]) );
}



1; # Magic true value required at end of module
__END__

=head1 NAME

Uc::IrcGateway - プラガブルなオレオレIRCゲートウェイ基底クラス


=head1 VERSION

This document describes Uc::IrcGateway version 3.0.0


=head1 SYNOPSIS

    package MyIrcGateway;
    use parent qw(Uc::IrcGateway);

    package main;

    my $ircd = MyIrcGateway->new(
        host => '0.0.0.0',
        port => 6667,
        time_zone => 'Asia/Tokyo',
        debug => 1,
    );

    $ircd->run();
    AE::cv->recv();


=head1 DESCRIPTION


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

No bugs have been reported.

Please report any bugs or feature requests to
L<https://github.com/UCormorant/p5-uc-ircgateway/issues>


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
