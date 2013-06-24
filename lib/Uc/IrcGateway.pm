package Uc::IrcGateway v3.0.0;
use 5.014;
use parent qw(Class::Component Object::Event);
use Uc::IrcGateway::Common;

use AnyEvent::Socket qw(tcp_server);
use DBD::SQLite 1.027;
use Carp qw(carp croak);
use Encode qw(find_encoding);
use Path::Class qw(file);
use Sys::Hostname qw(hostname);
use Scalar::Util qw(refaddr);
use IO::Socket::INET ();
use YAML::XS ();
use JSON::XS ();

use Class::Accessor::Lite (
    ro => [ qw(
        host
        port
        time_zone
        servername
        gatewayname
        daemon
        motd
        ping_timeout
        debug
        ctime

        handles
    )],
);

our %IRC_COMMAND_EVENT = ();
our %CTCP_COMMAND_EVENT = ();
our %CTCP_COMMAND_INFO = (
    clientinfo => 'CLIENTINFO with 0 arguments gives a list of known client query keywords. With 1 argument, a description of the client query keyword is returned.',
);

sub event_irc_command  { \%IRC_COMMAND_EVENT  }
sub event_ctcp_command { \%CTCP_COMMAND_EVENT }

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;
    my $self = $class->SUPER::new(\%args);

    $self->init_object_events();
    $self->{_init_object_events} = 1;

    # TODO: オプションの値チェック

    $self->{debug}        //= 0;
    $self->{host}         //= '127.0.0.1';
    $self->{port}         //= 6667;
    $self->{time_zone}    //= 'local';
    $self->{servername}   //= scalar hostname();
    $self->{gatewayname}  //= '*ucircd';
    $self->{ping_timeout} //= 30;
    $self->{charset}      //= 'utf8';
    $self->{err_charset}  //= $^O eq 'MSWin32' ? 'cp932' : 'utf8';

    $self->{codec}     = find_encoding($self->charset);
    $self->{err_codec} = find_encoding($self->err_charset);

    $self->{motd}      = file($self->{motd} || $0 =~ s/(.*)\.\w+$/$1.motd.txt/r);
    $self->{daemon}    = Uc::IrcGateway::User->new(nick => $self->gatewayname);
    $self->{codec}     = find_encoding($self->charset);
    $self->{err_codec} = find_encoding($self->err_charset);

    $self->{handles} = {};

    my $irc_event = $self->event_irc_command;
    my $ctcp_event = $self->event_ctcp_command;
    for my $event ((values $irc_event), (values $ctcp_event)) {
        say "$event->{name}";
        $event->{guard} = $self->reg_cb($event->{name} => $event->{code});
    }

    $self->reg_cb(
        on_eof => sub {
            my ($self, $handle) = @_;
        },
        on_error => sub {
            my ($self, $handle, $fatal, $message) = @_;
            carp "[$fatal] $message";
        },
    );

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
        my $handle = Uc::IrcGateway::Connection->new(
            fh => $fh,
            ircd => $self,

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

        say "Starting '@{[ $self->servername ]}' is succeed.";
        say "@{[ $self->servername ]} settings:";
        say "   - Listen on @{[ $self->host.':'.$self->port ]}";
        say "   - Server created at @{[ $self->ctime ]}";
        say "   - Server time zone is @{[ $self->time_zone ]}";
        say "   - Gateway bot is @{[ $self->gatewayname ]}";
#        say "   - Setting files are in @{[ $self->set_dir ]}";
        say "   - Message Of The Day uses @{[ scalar $self->motd ]}";

        if ($self->debug) {
            say "IRC/CTCP command list:" ;
            my $irc_event = $self->event_irc_command;
            my $ctcp_event = $self->event_ctcp_command;
            for my $command (sort keys $irc_event) {
                say sprintf "    IRC: %s => %s::%s", uc($command), ref $irc_event->{$command}{plugin}, $irc_event->{$command}{method};
            }
            for my $command (sort keys $ctcp_event) {
                say sprintf "    CTCP: %s => %s::%s", uc($command), ref $ctcp_event->{$command}{plugin}, $ctcp_event->{$command}{method};
            }
        }
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
    my $event = uc($msg->{command} || '');
       $event = exists $IRC_COMMAND_EVENT{$event} ? "irc_event_$event" : 'irc';

    $self->logger($handle, debug => "handle_irc_msg: $raw, ".JSON::XS->new->pretty(1)->encode(\%opts));
    $msg->{raw} = $raw;
    $msg->{$_}  = $opts{$_} for keys %opts;
    $self->event($event, $handle => $msg);
}

sub handle_ctcp_msg {
    my ($self, $handle, $raw, %opts) = @_;
    my ($msg, $event) = {};

    @{$msg}{qw/command params/} = split(' ', $raw, 2);
    $msg->{params} = [$msg->{params}];
    $event = uc($msg->{command});
    $event = exists $CTCP_COMMAND_EVENT{$event} ? "ctcp_event_$event" : 'ctcp';

    $self->logger($handle, debug => "handle_ctcp_msg: $raw, ".JSON::XS->new->pretty(1)->encode(\%opts));
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
        $self->logger($handle, debug => "send_cmd: $msg");
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
    __PACKAGE__->load_plugins(qw/DefaultSet/);

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
