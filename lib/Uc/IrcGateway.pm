package Uc::IrcGateway v3.1.1;
use 5.014;
use parent qw(Class::Component Object::Event);
use Uc::IrcGateway::Common;
__PACKAGE__->load_components(qw/Autocall::Autoload/);

use AnyEvent::Socket qw(tcp_server);
use Carp qw(carp croak);
use Encode qw(find_encoding);
use Path::Class qw(file dir);
use Sys::Hostname qw(hostname);
use Scalar::Util qw(blessed refaddr);
use Text::InflatedSprintf qw(inflated_sprintf);
use IO::Socket::INET ();

use Class::Accessor::Lite (
    rw => [qw(
        debug
        time_zone
        servername
        gatewayname

        motd_file
        motd_text
        app_dir
        ping_timeout
    )],
    ro => [qw(
        condvar

        host
        port
        daemon
        ctime
        message_set

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
    $self->{motd_file}    //= file($0)->basename =~ s/(.*)\.\w+$/$1.motd.txt/r;
    $self->{motd_text}    //= undef;

    $self->{message_set}  //= +{};

    $self->{codec}     = find_encoding($self->charset);
    $self->{err_codec} = find_encoding($self->err_charset);

    $self->{daemon}    = Uc::IrcGateway::TempUser->new(nick => $self->gatewayname, login => '*', host => $self->host, registered => 1);

    $self->{app_dir}   = $self->{app_dir} ? dir($self->{app_dir}) : $self->default_app_dir();
    $self->{app_dir}->mkpath if not -e $self->{app_dir};
    $self->{motd_file} = file($self->app_dir, $self->{motd_file});
    chomp $self->{motd_text} if defined $self->{motd_text};

    $self->{handles}   = +{};

    # リプライメッセージの定義
    my $message_set = Uc::IrcGateway::Message->message_set;
    while (my ($message_key, $message_value) = each $message_set) {
        $self->{message_set}{$message_key} //= $message_value;
    }

    # IRCイベントの登録
    my $irc_event = $self->event_irc_command;
    my $ctcp_event = $self->event_ctcp_command;
    for my $event ((values $irc_event), (values $ctcp_event)) {
        $event->{guard} = $self->reg_cb($event->{name} => $event->{code});
    }

    # ロガーの準備
    $self->logger;
    $self->reg_cb( do_logging => sub { +shift->logger->log(@_); } );

    # コネクションハンドラのイベントの登録
    $self->reg_cb(
        on_handle_connect => sub { $_[0]->logger->log(info  => $_[1]) },
        on_handle_eof     => sub { $_[0]->logger->log(info  => $_[1]) },
        on_handle_error   => sub { $_[0]->logger->log(error => $_[1]) },
    );

    # 例外処理の登録
    $self->set_exception_cb(sub {
        my ($exception, $eventname) = @_;
        my $message = sprintf "callback exception on event '%s': %s", $eventname, $exception =~ s/[\r\n]+$//r;

        if ($self->condvar) {
            $self->logger->log(emerg => $message);
            $self->condvar->send;
        }
        else {
            $self->logger->log_and_die(emerg => $message);
        }
    });

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

            on_eof => sub {
                my $handle = shift;
                my $refaddr = refaddr $handle;
                $self->event('on_handle_eof', "handle{$refaddr} sent EOF: close connection by peer");
                delete $self->handles->{$refaddr};
            },
            on_error => sub {
                my ($handle, $fatal, $message) = @_;
                my $refaddr = refaddr $handle;
                $message = sprintf "[%s] handle{%s} sent an error: %s",
                    ($fatal ? 'fatal' : 'warn'), $refaddr, $message =~ s/$REGEX{chomp}//gr;
                $self->event('on_handle_error', $message);
                delete $self->handles->{$refaddr} if $fatal;
            },
        );
        $handle->on_read(sub {
            $_[0]->push_read(line => $REGEX{crlf}, sub {
                my ($handle, $line, $eol) = @_;
                $line =~ s/$REGEX{chomp}//g;
                $self->handle_irc_msg($handle, $self->codec->decode($line));
            });
        });

        $handle->self(Uc::IrcGateway::TempUser->new);

        my $refaddr = refaddr($handle);
        $self->handles->{$refaddr} = $handle;
        $self->event('on_handle_connect', "handle{$refaddr} meets @{[$self->servername]}.");
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
        say "   - Setting files are in @{[ $self->app_dir ]}";
        say "   - Message Of The Day uses @{[ $self->motd_text ? 'raw text' : scalar $self->motd_file ]}";

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

    $self->log($handle, debug => "handle_irc_msg: $raw, ".to_json(\%opts));
    $msg->{raw} = $raw;
    $msg->{$_}  = $opts{$_} for keys %opts;
    $self->event($event, $handle => $msg);
}

sub handle_ctcp_msg {
    my ($self, $handle, $raw, %opts) = @_;
    my ($msg, $event) = +{};

    @{$msg}{qw/command params/} = split(' ', $raw, 2);
    $msg->{params} = [$msg->{params}];
    $event = uc($msg->{command});
    $event = exists $CTCP_COMMAND_EVENT{$event} ? "ctcp_event_$event" : 'ctcp';

    $self->log($handle, debug => "handle_ctcp_msg: $raw, ".to_json(\%opts));
    $msg->{raw} = $raw;
    $msg->{$_}  = $opts{$_} for keys %opts;
    $self->event($event, $handle => $msg);
}


# server to client

sub send_reply {
    my ($self, $handle, $msg, $reply) = @_;
    if (not $self->check_connection($handle)) {
        $self->log($handle, error => "send_reply: $reply: connection not found");
        return;
    }
    $self->log($handle, debug => "send_reply: $reply, ".to_json($msg->{response}), $handle);

    my $reply_set = $self->message_set->{$reply};

    die "message set '$reply' is not defined" if not defined $reply_set;

    my $new_args = +{
        format => $reply_set->{format},
        maxbyte => ($reply_set->{trim_or_fileout} ? undef : $MAXBYTE-length($CRLF)),
    };
    for my $line (inflated_sprintf($new_args, $msg->{response})) {
        my @args;
        if ($line ne '') {
            @args = split / /, $line;
            if (scalar @args != 1) {
                my $index = 0;
                for my $i (0..$#args) {
                    $index = $i;
                    last if $args[$i] =~ /^:/;
                }
                $args[$index] .= join " ", '', splice @args, $index+1;
            }
            $args[-1] =~ s/^://;
        }

        my $reply_msg = mk_msg($self->to_prefix, $reply_set->{number}, ($handle->self->nick || '*'), @args);
           $reply_msg = $self->trim_message($reply_msg) if $reply_set->{trim_or_fileout};

        $self->log($handle, debug => "send_reply: $reply_msg");
        $handle->push_write($self->codec->encode($reply_msg) . $CRLF);
    }
}

sub send_msg {
    my ($self, $handle, $cmd, @args) = @_;
    $self->send_cmd($handle, $self->to_prefix, $cmd, $handle->self->nick, @args);
}

sub send_cmd {
    my ($self, $handle, $user, $cmd, @args) = @_;
    if (not $self->check_connection($handle)) {
        $self->log($handle, error => sprintf "send_cmd: %s: '%s'", $cmd, join "', '", @args);
        return;
    }

    my $prefix = blessed $user && $user->can('to_prefix') ? $user->to_prefix : $user ? $user : '*';
    my $msg = mk_msg($prefix, $cmd, @args);
       $msg = $self->trim_message($msg);

    $self->log($handle, debug => "send_cmd: $msg");
    $handle->push_write($self->codec->encode($msg) . $CRLF);
}

sub send_ctcp_query {
    my ($self, $handle, $user, $cmd, @args) = @_;
    $self->send_cmd( $handle, $user, 'PRIVMSG', $handle->self->nick, encode_ctcp([uc($cmd), @args]) );
}

sub send_ctcp_reply {
    my ($self, $handle, $user, $cmd, @args) = @_;
    $self->send_cmd( $handle, $user, 'NOTICE', $handle->self->nick, encode_ctcp([uc($cmd), @args]) );
}

sub send_welcome {
    my ($self, $handle) = @_;
    my $user = $handle->self;
    my $msg = +{ response => +{
        nick => $user->nick,
        user => $user->login,
        host => $user->host,
        servername => $self->servername,
        version => ref($self).'/'.$self->VERSION,
        date => $self->ctime,
        available_user_modes => '*',
        available_channel_modes => '*',
    } };

    $self->send_reply( $handle, $msg, 'RPL_WELCOME' );
    $self->send_reply( $handle, $msg, 'RPL_YOURHOST' );
    $self->send_reply( $handle, $msg, 'RPL_CREATED' );
    $self->send_reply( $handle, $msg, 'RPL_MYINFO' );

    $self->handle_irc_msg( $handle, 'MOTD' );
}


# other method

sub default_app_dir {
    my $self = shift;
    my $path = file($0);
    my ($dir, $app_dir) = ($path->dir, sprintf '.%s', $path->basename);

    if ($self->{app_dir_to_home}) {
        for my $home (qw/HOME USERPROFILE/) {
            if (exists $ENV{$home} and -e $ENV{$home}) {
                $dir = $ENV{$home}; last;
            }
        }
    }

    dir($dir, $app_dir);
}

sub check_connection {
    not blessed $_[1] or $_[1]->destroyed ? 0 : 1;
}

sub check_params {
    my ($self, $handle, $msg, $plugin) = @_;
    return 0 unless $self->check_connection($handle);

    my $count = $plugin->config->{require_params_count} || 0;

    if (scalar $msg->{params} < $count) {
        $msg->{response}{command} = $msg->{command};
        $self->send_reply( $handle, $msg, 'ERR_NEEDMOREPARAMS' );
        return 0;
    }

    return 1;
}

sub check_user {
    my ($self, $handle, $nick, %opt) = @_;
    if (not $handle->has_nick($nick)) {
        $self->send_msg( $handle, ERR_NOSUCHNICK, $nick, 'No such nick/channel' ) unless $opt{silent};
        return 0;
    }
    return 1;
}

sub check_channel {
    my ($self, $handle, $chan, %opt) = @_;
    if (not is_valid_channel_name($chan)) {
        $self->send_msg( $handle, ERR_NOSUCHCHANNEL, $chan, 'Invalid channel name' ) unless $opt{silent};
        return 0;
    }
    if (($opt{enable} || $opt{joined}) && !$handle->has_channel($chan)) {
        $self->send_msg( $handle, ERR_NOSUCHCHANNEL, $chan, 'No such channel' ) unless $opt{silent};
        return 0;
    }
    if ($opt{joined} && !$handle->get_channels($chan)->has_user($handle->self->login)) {
        $self->send_msg( $handle, ERR_NOTONCHANNEL, $chan, "You're not on that channel" ) unless $opt{silent};
        return 0;
    }
    if ($opt{operator} && !$handle->get_channels($chan)->is_operator($handle->self->login)) {
        $self->send_msg( $handle, ERR_CHANOPRIVSNEEDED, $chan, "You're not channel operator" ) unless $opt{silent};
        return 0;
    }
    return 1;
}

sub trim_message {
    my ($self, $message) = @_;
    chop $message while length $self->codec->encode($message).$CRLF > $MAXBYTE;

    $message;
}

sub log {
    my $self = shift;
    my $handle = shift;
    $self->event( do_logging => @_, $handle );
}

sub logger {
    my $self = shift;
    $self->{logger} //= Uc::IrcGateway::Logger->new(
        outputs => [
            [
                'Screen',
                min_level => ($self->debug ? 'debug' : 'info'),
                stderr    => 1,
                newline   => 1,
            ],
        ],
        callbacks => sub { my %p = @_; $self->err_codec->encode("[$p{level}] $p{message}"); },
    );
    $self->{logger};
}


1; # Magic true value required at end of module
__END__

=encoding utf8

=head1 NAME

Uc::IrcGateway - プラガブルなオレオレIRCゲートウェイ基底クラス


=head1 VERSION

This document describes Uc::IrcGateway version v3.1.1


=head1 SYNOPSIS

    package MyIrcGateway;
    use parent qw(Uc::IrcGateway);
    __PACKAGE__->load_plugins(qw/DefaultSet AutoRegisterUser/);

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


=head1 DIAGNOSTICS


=head1 CONFIGURATION AND ENVIRONMENT


=head1 DEPENDENCIES


=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
L<https://github.com/UCormorant/p5-uc-ircgateway/issues>


=head1 AUTHOR

U=Cormorant E<lt>u@chimata.orgE<gt>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011-2013, U=Cormorant. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
