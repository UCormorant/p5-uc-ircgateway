package Uc::IrcGateway;

use 5.010;
use common::sense;
use warnings qw(utf8);
use version; our $VERSION = qv('0.7.3');

use Any::Moose;
use Any::Moose qw(::Util::TypeConstraints);
use AnyEvent::Socket;
use AnyEvent::IRC::Util qw(
    mk_msg parse_irc_msg split_prefix decode_ctcp encode_ctcp
    prefix_nick prefix_user prefix_host is_nick_prefix join_prefix
);
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
subtype 'NoBlankedStr' => as 'Str'   => where { /^\S+$/ } => message { "This Str ($_) must not have any blanks!" };
coerce  'NoBlankedStr' => from 'Str' => via { s/\s+//g; $_ };
has 'host' => ( is => 'ro', isa => 'Str', required => 1, default => '127.0.0.1' );
has 'port' => ( is => 'ro', isa => 'Int', required => 1, default => 6667 );
has 'servername'  => ( is => 'rw', isa => 'Str', required => 1, default => sub { hostname() } );
has 'gatewayname' => ( is => 'rw', isa => 'NoBlankedStr', required => 1, default => 'ucircgateway' );
has 'welcome'    => ( is => 'rw', isa => 'Str', default => 'welcome to my irc server' );
has 'ctime'      => ( is => 'ro', isa => 'Str', lazy => 1, builder => sub { scalar localtime } );
has 'admin'      => ( is => 'ro', isa => 'Str', default => 'nobody' );
has 'password'   => ( is => 'ro', isa => 'NoBlankedStr');
has 'motd'      => ( is => 'ro', isa => 'Path::Class::File', default => sub { (my $file = $0) =~ s/\.\w+$//; file("$file.motd.txt") } );
has 'time_zone' => ( is => 'rw', isa => 'Str', default => 'local' );
has 'daemon' => ( is => 'ro', isa => 'Uc::IrcGateway::Util::User', lazy => 1, builder => sub {
    my $self = shift;
    my $gatewayname = $self->gatewayname;
    Uc::IrcGateway::Util::User->new(
        nick => $gatewayname, login => $gatewayname, realname => $self->admin,
        host => $self->host, addr => $self->servername, server => $self->servername,
    );
});

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
    nick user
    join part
    topic privmsg notice
    names list who whois
    ison

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
    clientinfo
    action
);
our %CTCP_COMMAND_INFO = (
    clientinfo => 'CLIENTINFO with 0 arguments gives a list of known client query keywords. With 1 argument, a description of the client query keyword is returned.',
);

{
    local $_;
    no strict 'refs';
    $IRC_COMMAND_EVENT{'irc'}  = \&_event_irc;
    $IRC_COMMAND_EVENT{'ctcp'} = \&_event_ctcp;
    for (@IRC_COMMAND_LIST_ALL) {
        when (\@IRC_COMMAND_LIST) { $IRC_COMMAND_EVENT{"irc_$_"} = \&{"_event_irc_$_"} }
        default { $IRC_COMMAND_EVENT{"irc_$_"} = \&_event_irc; }
    }
    for (@CTCP_COMMAND_LIST_ALL) {
        when (\@CTCP_COMMAND_LIST) { $CTCP_COMMAND_EVENT{"ctcp_$_"} = \&{"_event_ctcp_$_"} }
        default { $CTCP_COMMAND_EVENT{"ctcp_$_"} = \&_event_ctcp; }
    }
}

our $CRLF = "\015\012";
our $MAXBITE = 512;
our %REGEX = (
    chomp        => qr{[\015\012\0]+$},
    channel_name => qr{^[#&][^\#&\s,]+$},
);
our @EXPORT = qw(
    check_params is_valid_channel_name

    mk_msg parse_irc_msg split_prefix decode_ctcp encode_ctcp
    prefix_nick prefix_user prefix_host is_nick_prefix join_prefix

    $VERSION $CRLF $MAXBITE
    %IRC_COMMAND_EVENT %CTCP_COMMAND_EVENT
    @IRC_COMMAND_LIST  @IRC_COMMAND_LIST_ALL
    @CTCP_COMMAND_LIST @CTCP_COMMAND_LIST_ALL
    %CTCP_COMMAND_INFO

);
push @EXPORT, values %AnyEvent::IRC::Util::RFC_NUMCODE_MAP;

__PACKAGE__->meta->make_immutable;
no Any::Moose;

sub BUILD {}
sub run {
    my $self = shift;

    say "Starting irc gateway server on @{[ $self->host.':'.$self->port ]}";

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
            $line =~ s/$REGEX{chomp}//g;
            $self->handle_irc_msg($handle, $line);
        }) });
    }, sub {
        my ($fh, $host, $port) = @_;
        $self->ctime;

        say "Bound to $host:$port";
        say "Starting '@{[ $self->servername ]}' is succeed.";
        say "@{[ $self->servername ]} settings:";
        say "   - Listen on @{[ $self->host.':'.$self->port ]}";
        say "   - Server created at @{[ $self->ctime ]}";
        say "   - Server time zone is @{[ $self->time_zone ]}";
        say "   - Gateway bot is @{[ $self->gatewayname ]}";
        say "   - Message Of The Day uses @{[ scalar $self->motd ]}";
    };
}


# event function ( irc command ) #

sub _event_irc {
    my ($self, $handle, $msg) = @_;
    my $cmd  = $msg->{command};

    # <command> is not implemented
    $self->send_msg( $handle, ERR_UNKNOWNCOMMAND, $cmd, "is not implemented" );

    @_;
}

sub _event_irc_nick {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self;

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

sub _event_irc_user {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self;

    my ($login, $host, $server, $realname) = @{$msg->{params}};
    my $user = $handle->self;
    return () unless $user;

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

sub _event_irc_join {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self;

    my $chans = $msg->{params}[0];
    my $nick = $handle->self->nick;

    for my $chan (split /,/, $chans) {
        next unless $self->check_channel( $handle, $chan );
        next if     $self->check_channel( $handle, $chan, joined => 1, silent => 1 );

        $handle->set_channels($chan => Uc::IrcGateway::Util::Channel->new(name => $chan) ) if !$handle->has_channel($chan);
        $handle->get_channels($chan)->join_users($handle->self->login => $nick);

        # send join message
        $self->send_cmd( $handle, $handle->self, 'JOIN', $chan );

        # sever reply
        $self->send_msg( $handle, RPL_TOPIC, $chan, $handle->get_channels($chan)->topic || '' );
        $self->handle_irc_msg( $handle, "NAMES $chan" );
        $self->send_cmd( $handle, $self->daemon, 'MODE', $chan, '+o', $nick );

        push @{$msg->{success}}, $chan;
    }

    @_;
}

sub _event_irc_part {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self;

    my ($chans, $text) = @{$msg->{params}};
    my $login = $handle->self->login;

    for my $chan (split /,/, $chans) {
        next unless $self->check_channel( $handle, $chan, joined => 1 );

        $handle->get_channels($chan)->part_users($login);

        # send part message
        $self->send_cmd( $handle, $handle->self, 'PART', $chan, $text );

        delete $handle->channels->{$chan} if !$handle->get_channels($chan)->user_count;
        push @{$msg->{success}}, $chan;
    }

    @_;
}

sub _event_irc_topic {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self;

    my ($chan, $topic) = @{$msg->{params}};
    return () unless $self->check_channel( $handle, $chan, enable => 1 );

    if ($topic) {
        # send topic message
        my $prefix = $msg->{prefix} || $handle->self;
        $self->send_cmd( $handle, $prefix, 'TOPIC', $chan, $topic );

        # server reply
        $handle->get_channels($chan)->topic( $topic );
        $self->send_msg( $handle, RPL_TOPIC, $chan, $topic );
    }
    elsif (defined $topic) {
        $self->send_msg( $handle, RPL_NOTOPIC, $chan, 'No topic is set' );
    }
    else {
        $self->send_msg( $handle, RPL_TOPIC, $chan, $handle->get_channels($chan)->topic );
    }

    @_;
}

sub _event_irc_privmsg {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self;

    my ($target, $text) = @{$msg->{params}};
    return () unless
         is_valid_channel_name($target) && $self->check_channel( $handle, $target, enable => 1 )
             or $self->check_user( $handle, $target );

    # send privmsg message
    $self->send_cmd( $handle, $handle->self, 'PRIVMSG', $target, $text );

    @_;
}

sub _event_irc_notice {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self;

    my ($chan, $topic) = @{$msg->{params}};

    # no reply is sent

    @_;
}

sub _event_irc_ping {
    my ($self, $handle, $msg) = @_;
    @_;
}
sub _event_irc_pong { @_; }

sub _event_irc_names {
    my ($self, $handle, $msg) = @_;
    my $chans = $msg->{params}[0] || join ',', sort $handle->channel_list;

    for my $chan (split /,/, $chans) {
        next unless $self->check_channel( $handle, $chan, enable => 1 );
        my $c = $handle->get_channels($chan);
#        my @names;
#        for my $name ($c->user_list) {
#            my $m = $c->get_users($name)->mode;
#            push @names, ($m->{o} ? '@' : $m->{m} ? '+' : '') . $name;
#        }
#        $self->send_msg( $handle, RPL_NAMREPLY, $chan, ':'.join ',', @names );
        my $users = '';
        my $users_test = mk_msg($self->daemon->to_prefix, RPL_NAMREPLY, $handle->self->nick, '*', $chan, '');
        for my $user (sort $c->nick_list) {
            if (length "$users_test$users $user$CRLF" > $MAXBITE) {
                $self->send_msg( $handle, RPL_NAMREPLY, '*', $chan, $users );
                $users = $user;
            }
            else {
                $users .= $users ? " $user" : $user;
            }
        }
        $self->send_msg( $handle, RPL_NAMREPLY, '*', $chan, $users );
        $self->send_msg( $handle, RPL_ENDOFNAMES, '*', $chan, 'End of /NAMES list' );
    }

    @_;
}

sub _event_irc_list {
    my ($self, $handle, $msg) = @_;
    my $chans = $msg->{params}[0] || join ',', sort $handle->channel_list;
    my $nick = $handle->self->nick;

    # too old message spec
    #$self->send_msg( $handle, RPL_LISTSTART, $nick, 'Channel', 'Users Name' );
    for my $channel ($handle->get_channels(split /,/, $chans)) {
        ### $channel
        next unless $channel;
        my $member_count = scalar $channel->login_list;
        $self->send_msg( $handle, RPL_LIST, $channel->name, $member_count, $channel->topic );
    }
    $self->send_msg( $handle, RPL_LISTEND, 'END of /List' );

    @_;
}

sub _event_irc_who {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self;

    my ($check, $oper) = @{$msg->{params}};
    my @channels;

    # TODO: いまのところ channel, nick の完全一致チェックしにか対応してません
    if (!$check) {
        @channels = grep {
            not $self->check_channel($handle, $_, joined => 1, silent => 1);
        } $handle->channel_list;
        @channels = $handle->get_channels(@channels);
    }
    elsif ($handle->has_channel($check)) {
        @channels = $handle->get_channels($check);
    }
    else {
        @channels = ();
    }

    if (scalar @channels) {
        for my $channel (@channels) {
            for my $u ($handle->get_users($channel->nick_list)) {
                $self->send_msg( $handle, RPL_WHOREPLY, $channel->name, $u->login, $u->host, $u->server, $u->nick, 'H', '1 '.$u->realname);
            }
            $self->send_msg( $handle, RPL_ENDOFWHO, $channel->name, 'END of /WHO List');
        }
    }
    else {
        my $u = $handle->get_users($check);
        $self->send_msg( $handle, RPL_WHOREPLY, '*', $u->login, $u->host, $u->server, $u->nick, 'H', '1 '.$u->realname) if $u;
        $self->send_msg( $handle, RPL_ENDOFWHO, '*', 'END of /WHO List');
    }

    @_;
}

sub _event_irc_whois {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self;

    my $nicks = $msg->{params}[0];

    # TODO: mask (ワイルドカード)
    for my $user ($handle->get_users(split /,/, $nicks)) {
        next unless $user;

        $self->send_msg( $handle, RPL_AWAY, $user->nick, $user->away_message ) if $user->away_message;
        $self->send_msg( $handle, RPL_WHOISUSER, $user->nick, $user->login, $user->host, '*', $user->realname );
        $self->send_msg( $handle, RPL_WHOISSERVER, $user->nick, $user->server, $user->server );
        $self->send_msg( $handle, RPL_WHOISOPERATOR, $user->nick, 'is an IRC operator' );
        $self->send_msg( $handle, RPL_WHOISIDLE, $user->nick, time - $user->last_modified, 'seconds idle' );
        $self->send_msg( $handle, RPL_WHOISCHANNELS, $user->nick, join ' ', $handle->who_is_channels($user->login) );
        $self->send_msg( $handle, RPL_ENDOFWHOIS, $user->nick, 'End of /WHOIS list' );
    }

    @_;
}

sub _event_irc_ison {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self;

    my @users;
    for my $nick (@{$msg->{params}}) {
        push @users, $nick if $handle->has_user($nick);
    }

    $self->send_msg( $handle, RPL_ISON, join ' ', @users );

    @_;
}

sub _event_irc_quit {
    my ($self, $handle, $msg) = @_;
    @_;
}


# event function ( ctcp command ) #

sub _event_ctcp {
    my ($self, $handle, $msg, $reply) = @_;

    # <query> is unknown
    $self->send_ctcp_reply( $handle, $self->daemon, 'ERROR', $msg->{raw}, ':Query is unknown' );

    @_;
}

sub _event_ctcp_finger {}
sub _event_ctcp_userinfo {}
sub _event_ctcp_time {}
sub _event_ctcp_version {}
sub _event_ctcp_source {}

sub _event_ctcp_clientinfo {
    my ($self, $handle, $msg) = @_;
    my $command = $msg->{command};
    my $param   = $msg->{params}[0];
    my $text    = $param && exists $CTCP_COMMAND_INFO{lc $param} ? $CTCP_COMMAND_INFO{lc $param}
                                                               : uc(join ' ', @CTCP_COMMAND_LIST);

    $self->send_ctcp_reply( $handle, $self->daemon, $command, ":$text" );

    @_;
}

sub _event_ctcp_errmsg {}
sub _event_ctcp_ping {}
sub _event_ctcp_action {}


# public function #

sub check_params {
    my ($self, $handle, $msg) = @_;
    my $cmd   = $msg->{command};
    my $param = $msg->{params}[0];

    unless ($param) {
        $self->need_more_params($handle, $cmd);
        return ();
    }

    @_;
}

sub is_valid_channel_name { $_[0] =~ /$REGEX{channel_name}/; }


# IrcGateway method #

# client to server
sub handle_irc_msg {
    my ($self, $handle, $raw) = @_;
    my $msg   = parse_irc_msg($raw);
    my $event = lc($msg->{command});
       $event = exists $IRC_COMMAND_EVENT{"irc_$event"} ? "irc_$event" : 'irc';

    ### $raw
    $msg->{raw} = $raw;
    $self->event($event, $handle => $msg);
}

sub handle_ctcp_msg {
    my ($self, $handle, $raw, %opts) = @_;
    my ($msg, $event) = {};

    @{$msg}{qw/command params/} = split(' ', $raw, 2);
    $event = lc($msg->{command});
    $event = exists $CTCP_COMMAND_EVENT{"ctcp_$event"} ? "ctcp_$event" : 'ctcp';

    ### $raw
    $msg->{raw}    = $raw;
    $msg->{reply}  = $opts{reply};
    $msg->{target} = $opts{target};
    $self->event($event, $handle => $msg);
}

# server to client
sub send_msg {
    my ($self, $handle, $cmd, @args) = @_;
    my $msg = mk_msg($self->daemon->to_prefix, $cmd, $handle->self->nick, @args);
    # $msg
    $handle->push_write($msg . $CRLF);
}

sub send_cmd {
    my ($self, $handle, $user, $cmd, @args) = @_;
    my $prefix = ref $user eq 'Uc::IrcGateway::Util::User' ? $user->to_prefix : $user;
    my $msg = mk_msg($prefix, $cmd, @args);
    # $msg
    $handle->push_write($msg . $CRLF);
}

sub send_ctcp_query {
    my ($self, $handle, $user, $cmd, @args) = @_;
    $self->send_cmd( $handle, $user, 'PRIVMSG', ':'.encode_ctcp([':'.uc($cmd), @args]) );
}

sub send_ctcp_reply {
    my ($self, $handle, $user, $cmd, @args) = @_;
    $self->send_cmd( $handle, $user, 'NOTICE',  encode_ctcp([':'.uc($cmd), @args]) );
}

sub need_more_params {
    my ($self, $handle, $cmd) = @_;
    $self->send_msg($handle, ERR_NEEDMOREPARAMS, $cmd, 'Not enough parameters');
}

sub check_user {
    my ($self, $handle, $nick, %opt) = @_;
    if (not $handle->has_user($nick)) {
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
