package Uc::IrcGateway;

use 5.010;
use common::sense;
use warnings qw(utf8);
use version; our $VERSION = qv('2.0.0');

use Any::Moose;
use Any::Moose qw(::Util::TypeConstraints);
use AnyEvent::Socket;
use AnyEvent::IRC::Util qw(
    mk_msg parse_irc_msg split_prefix decode_ctcp encode_ctcp
    prefix_nick prefix_user prefix_host is_nick_prefix join_prefix
);
use Uc::IrcGateway::Logger;
use Carp qw(carp croak);
use Encode qw(find_encoding);
use Path::Class qw(file);
use Sys::Hostname qw(hostname);
use Scalar::Util qw(refaddr);
use IO::Socket::INET;
use UNIVERSAL::which;
use Data::Dumper qw(Dumper);

BEGIN {
    $Data::Dumper::Terse = 1;

    no strict 'refs';
    while (my ($code, $name) = each %AnyEvent::IRC::Util::RFC_NUMCODE_MAP) {
        *{"${name}"} = sub () { $code };
    }
}

our $MAXBYTE = 512;
our $NUL      = "\0";
our $BELL     = "\07";
our $CRLF     = "\015\012";
our $SPECIAL  = '\[\]\\\`\_\^\{\|\}';
our $SPCRLFCL = " $CRLF:";
our %REGEX = (
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

extends qw/Object::Event Exporter/;
subtype 'NoBlankedStr'  => as 'Str'   => where { /^\S+$/ } => message { "This Str ($_) must not have any blanks!" };
coerce  'NoBlankedStr'  => from 'Str' => via { s/\s+//g; $_ };
subtype 'ValidNickName' => as 'Str' => where { /$REGEX{nickname}/ } => message { "This Str ($_) is not a valid nickname!" };
subtype 'ValidChanName' => as 'Str' => where { /$REGEX{channel}/  } => message { "This Str ($_) is not a valid channel name!" };

# handle (refaddr($handle) => $handle)
has 'handles' => ( is => 'ro', isa => 'HashRef[Uc::IrcGateway::Connection]', required => 1, default => sub { {} } );
# server host
has 'host' => ( is => 'ro', isa => 'Str', required => 1, default => '127.0.0.1' );
# listen port
has 'port' => ( is => 'ro', isa => 'Int', required => 1, default => 6667 );
# login password
has 'password' => ( is => 'ro', isa => 'NoBlankedStr');
# operator password
has 'operator_password' => ( is => 'ro', isa => 'NoBlankedStr');
# server hostname for message
has 'servername' => ( is => 'rw', isa => 'Str', required => 1, default => sub { scalar hostname() } );
# server created ctime
has 'ctime' => ( is => 'ro', isa => 'Str', lazy => 1, builder => sub { scalar localtime } );
# message of the day file path
has 'motd' => ( is => 'ro', isa => 'Path::Class::File', default => sub { (my $file = $0) =~ s/\.\w+$//; file("$file.motd.txt") } );
# server time zone
has 'time_zone' => ( is => 'rw', isa => 'Str', required => 1, default => 'local' );
# server character set
has 'charset' => ( is => 'rw', isa => 'Str', required => 1, default => 'UTF-8' );
# server character code encoder/decoder
has 'codec' => ( is => 'ro', isa => 'Object', lazy => 1, builder => sub { find_encoding($_[0]->charset) } );
# server character set
has 'err_charset' => ( is => 'rw', isa => 'Str', required => 1, default => sub { $^O eq 'MSWin32' ? 'cp932' : 'utf8' } );
# server character code encoder/decoder
has 'err_codec' => ( is => 'ro', isa => 'Object', lazy => 1, builder => sub { find_encoding($_[0]->err_charset) } );
# welcome message when USER command succeed
has 'welcome' => ( is => 'rw', isa => 'Str', default => 'welcome to my irc server' );
# gateway daemon name
has 'gatewayname' => ( is => 'rw', isa => 'ValidNickName', required => 1, default => 'ucircgateway' );
# gateway daemon realname
has 'admin' => ( is => 'rw', isa => 'Str', default => 'nobody' );
# server daemon
has 'daemon' => ( is => 'ro', isa => 'Uc::IrcGateway::User', lazy => 1, builder => sub {
    my $self = shift;
    my $gatewayname = $self->gatewayname;
    Uc::IrcGateway::User->new(
        registered => 1,
        nick => $gatewayname, login => $gatewayname, realname => $self->admin,
        host => $self->host, addr => $self->servername, server => $self->servername,
    );
});
# log level
# debug flag
has [qw/log_level debug/] => ( is => 'rw', isa => 'Int', default => 0 );
# logger
has 'logger' => ( is => 'rw', isa => 'Uc::IrcGateway::Logger', lazy => 1, builder => sub {
    my $self = shift;
    Uc::IrcGateway::Logger->new( gateway => $self, log_level => $self->log_level, log_debug => $self->debug );
});

__PACKAGE__->meta->make_immutable;
no Any::Moose;
no Any::Moose qw(::Util::TypeConstraints);

sub run {
    my $self = shift;

    say "Starting irc gateway server on @{[ $self->host.':'.$self->port ]}";

    print "Checking the port is able to use... ";
    IO::Socket::INET->new(
        Proto => "tcp",
        PeerAddr => $self->host,
        PeerPort => $self->port,
        Timeout => "1",
    ) and croak "stop. @{[ $self->host.':'.$self->port ]} is already used.";

    # TODO: ポートを開けないアドレスのチェック
    my $check = IO::Socket::INET->new(
        Proto => "tcp",
        LocalAddr => $self->host,
        LocalPort => $self->port,
        Listen => 1,
    ) or croak "stop. $!";
    $check->listen or croak "stop. cannot listen @{[ $self->host.':'.$self->port ]}.";
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
        $handle->on_read(sub { $handle->push_read(line => sub {
            my ($handle, $line, $eol) = @_;
            $line =~ s/$REGEX{chomp}//g;
            $self->handle_irc_msg($handle, $self->codec->decode($line));
        }) });
        $self->handles->{refaddr($handle)} = $handle;
    }, sub {
        my ($fh, $host, $port) = @_;
        $self->ctime;

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
        say "   - Message Of The Day uses @{[ scalar $self->motd ]}";
    };
}


# event function ( irc command ) #

sub _event_irc {
    my ($self, $handle, $msg) = @_;
    my $cmd = $msg->{command};

    # <command> is not implemented
    $self->send_msg( $handle, ERR_UNKNOWNCOMMAND, $cmd, "is not implemented" );

    @_;
}

sub _event_irc_nick {
    my ($self, $handle, $msg) = @_;
    return () unless $self && $handle;

    my $cmd  = $msg->{command};
    my $nick = $msg->{params}[0];
    my $user = $handle->self;

    if ($nick eq '') {
        $self->send_msg( $handle, ERR_NONICKNAMEGIVEN, 'No nickname given' );
        return ();
    }
    elsif (not $nick =~ /$REGEX{nickname}/) {
        $self->send_msg( $handle, ERR_ERRONEUSNICKNAME, $nick, 'Erroneous nickname' );
        return ();
    }
    elsif ($handle->has_nick($nick) && defined $user && $handle->lookup($nick) ne $user->login) {
        $self->send_msg( $handle, ERR_NICKNAMEINUSE, $nick, 'Nickname is already in use' );
        return ();
    }

    if (defined $user && $user->nick) {
        # change nick
        $self->send_cmd( $handle, $user, $cmd, $nick );
        $handle->del_lookup($user->nick);
        $user->nick($nick);
        $handle->set_users($user);
    }
    elsif (defined $user) {
        # finish register user
        $user->nick($nick);
        $user->registered(1);
        $msg->{registered} = 1;
        $handle->set_users($user);
        $self->welcome_message( $handle );
    }
    else {
        # start register user
        $user = Uc::IrcGateway::User->new(
            nick => $nick, login => '*', realname => '*',
            host => '*', addr => '*', server => '*',
        );
        $handle->self($user);
    }

    @_;
}

sub _event_irc_user {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

    my ($login, $host, $server, $realname) = @{$msg->{params}};
    my $cmd  = $msg->{command};
    my $user = $handle->self;
    if (defined $user && $user->registered) {
        $self->send_msg( $handle, ERR_ALREADYREGISTRED, 'Unauthorized command (already registered)' );
        return ();
    }

    $host ||= '0'; $server ||= '*'; $realname ||= '';
    if (defined $user) {
        $user->login($login);
        $user->realname($realname);
        $user->host($host);
        $user->addr($self->host);
        $user->server($server);
        $user->registered(1);
        $msg->{registered} = 1;
        $handle->set_users($user);
        $self->welcome_message( $handle );
    }
    else {
        $user = Uc::IrcGateway::User->new(
            nick => '', login => $login, realname => $realname,
            host => $host, addr => $self->host, server => $server,
        );
        $handle->self($user);
    }

    @_;
}

sub _event_irc_motd {
    my ($self, $handle, $msg) = @_;
    my $missing = 1;
    if (-e $self->motd) {
        my $fh = $self->motd->open("<:encoding(@{[$self->charset]})");
        if (defined $fh) {
            $missing = 0;
            $self->send_msg( $handle, RPL_MOTDSTART, "- @{[$self->servername]} Message of the day - " );
            my $i = 0;
            while (my $line = $fh->getline) {
                chomp $line;
                $self->send_msg( $handle, RPL_MOTD, "- $line" );
            }
            $self->send_msg( $handle, RPL_ENDOFMOTD, 'End of /MOTD command' );
        }
    }
    if ($missing) {
        $self->send_msg( $handle, ERR_NOMOTD, 'MOTD File is missing' );
    }

    @_;
}

sub _event_irc_join {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

    my $chans = $msg->{params}[0];
    my $nick  = $handle->self->nick;
    my $login = $handle->self->login;

    for my $chan (split /,/, $chans) {
        next unless $self->check_channel( $handle, $chan );
        next if     $self->check_channel( $handle, $chan, joined => 1, silent => 1 );

        $handle->set_channels($chan => Uc::IrcGateway::Channel->new(name => $chan) ) if not $handle->has_channel($chan);
        $handle->get_channels($chan)->join_users($login => $nick);
        $handle->get_channels($chan)->give_operator($login => $nick);

        # send join message
        $self->send_cmd( $handle, $handle->self, 'JOIN', $chan );

        # sever reply
        $self->send_msg( $handle, RPL_TOPIC, $chan, $handle->get_channels($chan)->topic || '' );
        $self->handle_irc_msg( $handle, "NAMES $chan" );

        push @{$msg->{success}}, $chan;
    }

    @_;
}

sub _event_irc_part {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

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

sub _event_irc_mode {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

    my $cmd = $msg->{command};
    my ($target, @mode_list) = @{$msg->{params}};
    my $mode_params = join '', @mode_list;
    my $user = $handle->self;

    if (is_valid_channel_name($target)) {
        return () unless $self->check_channel($handle, $target);

        my $chan = $handle->get_channels($target);
        # <channel>  *( ( "-" / "+" ) *<modes> *<modeparams> )

        my $oper = '';
        my $mode_string  = '';
        my $param_string = '';
        while (my $mode = shift @mode_list) {
            for my $m (split //, $mode) {
                if ($m eq '+' or $m eq '-') {
                    $oper = $m; next;
                }
                given ($m) {
    #     O - "チャンネルクリエータ"の権限を付与
    #     o - チャンネルオペレータの特権を付与/剥奪
                    when ('o') {
                        $oper ||= '+';

                        my $target_nick  = shift @mode_list;
                        my $target_login = $handle->lookup($target);

                        if (not $chan->has_user($target_login)) {
                            $self->send_msg( $handle, ERR_USERNOTINCHANNEL, $target, $chan->name, "They aren't on that channel" );
                        }
                        elsif ($chan->is_operator($user->login)) {
                            if ($chan->is_operator($target_login) and $oper eq '-') {
                                $chan->deprive_operator($target_login, $target_nick);
                                $mode_string  ||= $oper; $mode_string .= $m;
                                $param_string &&= $param_string.' '; $param_string .= $target_nick;
                            }
                            elsif (!$chan->is_operator($target_login)) {
                                $chan->give_operator($target_login, $target_nick);
                                $mode_string  ||= $oper; $mode_string .= $m;
                                $param_string &&= $param_string.' '; $param_string .= $target_nick;
                            }
                        }
                    }
    #     v - ボイス特権を付与/剥奪
                    when ('v') {
                        $oper ||= '+';

                        my $target_nick  = shift @mode_list;
                        my $target_login = $handle->lookup($target);

                        if (not $chan->has_user($target_login)) {
                            $self->send_msg( $handle, ERR_USERNOTINCHANNEL, $target, $chan->name, "They aren't on that channel" );
                        }
                        elsif ($chan->is_speaker($user->login)) {
                            if ($chan->is_speaker($target_login) and $oper eq '-') {
                                $chan->deprive_voice($target_login, $target_nick);
                                $mode_string  ||= $oper; $mode_string .= $m;
                                $param_string &&= $param_string.' '; $param_string .= $target_nick;
                            }
                            elsif (!$chan->is_speaker($target_login)) {
                                $chan->give_voice($target_login, $target_nick);
                                $mode_string  ||= $oper; $mode_string .= $m;
                                $param_string &&= $param_string.' '; $param_string .= $target_nick;
                            }
                        }
                    }
    #     a - 匿名チャンネルフラグをトグル
    #     i - 招待のみチャンネルフラグをトグル
    #     m - モデレートチャンネルをトグル
    #     n - チャンネル外クライアントからのメッセージ遮断をトグル
    #     q - クワイエットチャンネルフラグをトグル
    #     p - プライベートチャンネルフラグをトグル
    #     s - シークレットチャンネルフラグをトグル
    #     r - サーバreopチャンネルフラグをトグル
    #     t - トピック変更をチャンネルオペレータのみに限定するかをトグル
                    when ([qw/a i m n q p s r t/]) {
                        $oper ||= '+';
                        $chan->mode->{$m} = $oper eq '-' ? 0 : 1;
                        $mode_string  ||= $oper; $mode_string .= $m;
                    }
    #
    #     k - チャンネルキー(パスワード)の設定／解除
    #     l - チャンネルのユーザ数制限の設定／解除
    #
    #     b - ユーザをシャットアウトする禁止(ban)マスクの設定／解除
    #     e - 禁止マスクに優先する例外マスクの設定／解除
    #     I - 自動的に招待のみフラグに優先する招待マスクの設定／解除
                    default {
                        $self->send_msg( $handle, ERR_UNKNOWNCOMMAND, $m, "is unknown mode char to me for @{[$chan->name]}" );
                    }
                }
            }
        }

        $self->send_msg( $handle, RPL_CHANNELMODEIS, $chan->name, $mode_string, grep defined, ($param_string || undef) ) if $mode_string;
        push @{$msg->{success}}, $mode_string, $param_string if $mode_string;
    }
    else {
        return () unless $self->check_user($handle, $target);

        if ($target ne $user->nick) {
            $self->send_msg( $handle, ERR_USERSDONTMATCH, 'Cannot change mode for other users' );
            return ();
        }

        # <nickname> *( ( "+" / "-" ) *( "i" / "w" / "o" / "O" / "r" ) )

        if ($mode_params eq '') {
            $self->send_msg( $handle, RPL_UMODEIS, $user->mode_string );
        }
        else {
            my $mode = $user->mode;
            my $mode_flag = (join '', keys %{$mode}) || $NUL;
            my $mode_string = '';
            my $oper = '+';
            my $oper_last = '';
            for my $char (split //, $mode_params) {
                if ($char =~ /[+-]/) {
                    $oper = $char;
                }
                elsif ($char !~ /[$mode_flag]/) {
                    $self->send_msg( $handle, ERR_UMODEUNKNOWNFLAG, 'Unknown MODE flag' );
                }
                else {
                    $mode->{$char} = $oper eq '-' ? 0 : 1;
                    $mode_string .= $oper ne $oper_last ? $oper.$char : $char;
                    $oper_last = $oper;
                }
            }

            $self->send_cmd( $handle, $user, 'MODE', $user->nick, $mode_string ) if $mode_string;
            push @{$msg->{success}}, $mode_string;
        }
    }

    @_;
}

sub _event_irc_topic {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

    my ($chan, $topic) = @{$msg->{params}};
    return () unless $self->check_channel( $handle, $chan, enable => 1 );

    if ($topic) {
        $handle->get_channels($chan)->topic( $topic );

        # send topic message
        my $prefix = $msg->{prefix} || $handle->self;
        $self->send_cmd( $handle, $prefix, 'TOPIC', $chan, $topic );
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
    return () unless $self && $handle;

    my $cmd    = $msg->{command};
    my $prefix = $msg->{prefix} || $handle->self->to_prefix;
    my ($msgtarget, $text) = @{$msg->{params}};
    my ($plain_text, $ctcp) = decode_ctcp($text);
    my $silent = $cmd eq 'NOTICE' ? 1 : 0;

    if (not defined $text) {
        $self->send_msg( $handle, ERR_NOTEXTTOSEND, 'No text to send' ) unless $silent;
        return ();
    }

    for my $target (split /,/, $msgtarget) {
        # TODO: error
        if (0) { # WILD CARD
            if (0) { # check wild card
                # ERR_NOTOPLEVEL <mask> :No toplevel domain specified
                # ERR_WILDTOPLEVEL <mask> <mask> :Wildcard in toplevel domain
                # ERR_TOOMANYTARGETS <target> :<error code> recipients. <abort message>
                # ERR_NORECIPIENT :No recipient given (<command>)
                next;
            }
        }
        elsif (is_valid_channel_name($target)) {
            if (0) { # check mode
                # ERR_CANNOTSENDTOCHAN <channel name> :Cannot send to channel
                next;
            }
        }
        elsif (not $self->check_user($handle, $target, silent => $silent)) {
            next;
        }
        else {
            my $user = $handle->get_users_by_nicks($target);
            $self->send_msg( $handle, RPL_AWAY, $target, $user->away_message ) if $user->mode->{a};
        }

        # ctcp event
        if (scalar @$ctcp) {
            for my $event (@$ctcp) {
                my ($ctcp_text, $ctcp_args) = @{$event};
                $ctcp_text .= " $ctcp_args" if $ctcp_args;
                $self->handle_ctcp_msg( $handle, $ctcp_text,
                        prefix => $prefix, target => $target, orig_command => $cmd, silent => $silent );
            }
        }

        # push target for override method
        push @{$msg->{success}}, $target;
    }

    # push plain text and ctcp
    push @{$msg->{params}}, $plain_text, $ctcp;

    @_;
}

*_event_irc_notice = \&_event_irc_privmsg;

sub _event_irc_ping { @_; }
sub _event_irc_pong { @_; }

sub _event_irc_names {
    my ($self, $handle, $msg) = @_;
    my $chans = $msg->{params}[0] || join ',', sort $handle->channel_list;
    my $server = $msg->{params}[1];

    if ($server) {
        # サーバマスク指定は対応予定なし
        $self->send_msg( $handle, ERR_NOSUCHSERVER, $server, 'No such server' );
        return ();
    }

    for my $chan (split /,/, $chans) {
        next unless $self->check_channel( $handle, $chan, enable => 1 );

        my $c = $handle->get_channels($chan);
        my $c_mode = $c->mode->{s} ? '@' : $c->mode->{p} ? '*' : '=';
        my $m_chan = $c_mode.' '.$chan;

        my $users = '';
        my @users_list = ();
        my $users_test = mk_msg($self->to_prefix, RPL_NAMREPLY, $handle->self->nick, $m_chan, '');
        for my $nick (sort $c->nick_list) {
            next unless $handle->has_nick($nick);
            my $u_login = $handle->lookup($nick);
            my $u_mode = $c->is_operator($u_login) ? '@' : $c->is_speaker($u_login) ? '+' : '';
            my $m_nick = $u_mode.$nick;
            if (length "$users_test$users$m_nick$CRLF" > $MAXBYTE) {
                chop $users;
                push @users_list, $users;
                $users = '';
            }
            $users .= "$m_nick ";
        }
        push @users_list, $users if chop $users;

        $self->send_msg( $handle, RPL_NAMREPLY, $m_chan, $_ ) for @users_list;
        $self->send_msg( $handle, RPL_ENDOFNAMES, $chan, 'End of /NAMES list' );
    }

    @_;
}

sub _event_irc_list {
    my ($self, $handle, $msg) = @_;
    my $chans = $msg->{params}[0] || join ',', sort $handle->channel_list;
    my $server = $msg->{params}[1];
    my $nick = $handle->self->nick;

    if ($server) {
        # サーバマスク指定は対応予定なし
        $self->send_msg( $handle, ERR_NOSUCHSERVER, $server, 'No such server' );
        return ();
    }

    # too old message spec
    #$self->send_msg( $handle, RPL_LISTSTART, $nick, 'Channel', 'Users Name' );
    for my $channel ($handle->get_channels(split /,/, $chans)) {
        next unless $channel;
        my $member_count = scalar $channel->login_list;
        $self->send_msg( $handle, RPL_LIST, $channel->name, $member_count, $channel->topic );
    }
    $self->send_msg( $handle, RPL_LISTEND, 'END of /List' );

    @_;
}

sub _event_irc_invite {
    my ($self, $handle, $msg) = check_params(@_);
    my $cmd    = $msg->{command};
    my ($target, $channel) = @{$msg->{params}};

    return () unless $self->check_user($handle, $target);

    my $t_user = $handle->get_users_by_nicks($target);

    if ($self->check_channel($handle, $channel, enable => 1, silent => 1)) {
        my $chan = $handle->get_channels($channel);
        if (not $chan->has_user($handle->self->login)) {
            $self->send_msg( $handle, ERR_NOTONCHANNEL, $channel, "You're not on that channel" );
            return ();
        }
        if ($chan->has_user($t_user->login)) {
            $self->send_msg( $handle, ERR_USERONCHANNEL, $target, $channel, 'is already on channel' );
            return ();
        }
        if (not $chan->is_operator($handle->self->login)) {
            $self->send_msg( $handle, ERR_CHANOPRIVSNEEDED, $channel, "You're not channel operator" );
            return ();
        }
    }

    if ($t_user->mode->{a}) {
        $self->send_msg( $handle, RPL_AWAY, $target, $t_user->away_message );
    }

    # send invite message
    $self->send_cmd( $handle, $handle->self, 'INVITE', $target, $channel );

    # send server reply
    $self->send_cmd( $handle, $handle->self, RPL_INVITING, $channel, $target );

    @_;
}

sub _event_irc_kick {}

sub _event_irc_who {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

    my ($mask, $oper) = @{$msg->{params}};
    my @channels;

    # TODO: いまのところ channel, nick の完全一致チェックしにか対応してません
    if (!$mask || $mask eq '0') {
        @channels = grep {
            not $self->check_channel($handle, $_, joined => 1, silent => 1);
        } $handle->channel_list;
        @channels = $handle->get_channels(@channels);
    }
    elsif ($handle->has_channel($mask)) {
        @channels = $handle->get_channels($mask);
    }
    else {
        @channels = ();
    }

    if (scalar @channels) {
        for my $channel (@channels) {
            my $c_name = $channel->mode->{p} ? '*' : $channel->name;
            for my $u ($handle->get_users($channel->login_list)) {
                my $mode = $u->mode->{a} ? 'G' : 'H';
                $mode .= "*" if $u->mode->{o}; # server operator
                $mode .= $channel->is_operator($u->login) ? '@' : $channel->is_speaker($u->login) ? '+' : '';
                $self->send_msg( $handle, RPL_WHOREPLY, $c_name, $u->login, $u->host, $u->server, $u->nick, $mode, '0 '.$u->realname);
            }
            $self->send_msg( $handle, RPL_ENDOFWHO, $channel->name, 'END of /WHO List');
        }
    }
    else {
        my $u = $handle->get_users($mask);
        if ($u) {
            my $mode = $u->mode->{a} ? 'G' : 'H';
            $mode .= "*" if $u->mode->{o}; # server operator
            $self->send_msg( $handle, RPL_WHOREPLY, '*', $u->login, $u->host, $u->server, $u->nick, $mode, '0 '.$u->realname);
        }
        $self->send_msg( $handle, RPL_ENDOFWHO, '*', 'END of /WHO List');
    }

    @_;
}

sub _event_irc_whois {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

    my @nick_list = map { $self->check_user($handle, $_) ? $_ : () } split /,/, $msg->{params}[0];

    # TODO: mask (ワイルドカード)
    for my $user ($handle->get_users_by_nicks(@nick_list)) {
        next unless $user;

        my $channels = '';
        my @channel_list = ();
        my $channels_test = mk_msg($self->to_prefix, RPL_WHOISCHANNELS, $user->nick, '');
        for my $chan ($handle->who_is_channels($user->login)) {
            if (length "$channels_test$channels$chan$CRLF" > $MAXBYTE) {
                chop $channels;
                push @channel_list, $channels;
                $channels = '';
            }
            $channels .= "$chan ";
        }
        push @channel_list, $channels if chop $channels;

        $self->send_msg( $handle, RPL_AWAY, $user->nick, $user->away_message ) if $user->mode->{a};
        $self->send_msg( $handle, RPL_WHOISUSER, $user->nick, $user->login, $user->host, '*', $user->realname );
        $self->send_msg( $handle, RPL_WHOISSERVER, $user->nick, $user->server, $user->server );
        $self->send_msg( $handle, RPL_WHOISOPERATOR, $user->nick, 'is an IRC operator' ) if $user->mode->{o};
        $self->send_msg( $handle, RPL_WHOISIDLE, $user->nick, time - $user->last_modified, 'seconds idle' );
        $self->send_msg( $handle, RPL_WHOISCHANNELS, $user->nick, $_ ) for @channel_list;
        $self->send_msg( $handle, RPL_ENDOFWHOIS, $user->nick, 'End of /WHOIS list' );
    }

    @_;
}

sub _event_irc_away {
    my ($self, $handle, $msg) = @_;
    return () unless $self && $handle;

    my $cmd  = $msg->{command};
    my $text = $msg->{params}[0];

    $handle->self->mode->{a} = $text eq '' ? 0 : 1;
    $self->send_cmd( $handle, $self->to_prefix, RPL_UNAWAY,  'You are no longer marked as being away' ) if not $handle->self->mode->{a};
    $self->send_cmd( $handle, $self->to_prefix, RPL_NOWAWAY, 'You have been marked as being away' )     if     $handle->self->mode->{a};

    @_;
}

sub _event_irc_ison {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

    my @users;
    for my $nick (@{$msg->{params}}) {
        push @users, $nick if $handle->has_user($nick);
    }

    $self->send_msg( $handle, RPL_ISON, join ' ', @users );

    @_;
}

sub _event_irc_quit {
    my ($self, $handle, $msg) = @_;
    my $prefix = $msg->{prefix} || $handle->self->to_prefix;
    my $quit_msg = $msg->{params}[0];
    my ($nick, $login, $host) = split_prefix($prefix);

    # send error to accept quit # NOTE: うまくいってるのかわかんない
    $self->send_cmd( $handle, $prefix, 'ERROR', qq|Closing Link: $nick\[$login\@$host\] ("$quit_msg")| );
    undef $handle;
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
sub _event_ctcp_userinfo {
    my ($self, $handle, $msg) = @_;
    my ($cmd, $orig_cmd) = @{$msg}{qw/command orig_command/};
    my $prefix = $msg->{prefix};
    my $target = $msg->{target};
    my $param  = $msg->{params}[0];

    my $user = $handle->get_users_by_nicks($target);
    $self->send_ctcp_reply( $handle, $user, $cmd, $param ) unless $msg->{silent};

    @_;
}
sub _event_ctcp_time {}
sub _event_ctcp_version {}
sub _event_ctcp_source {}

sub _event_ctcp_clientinfo {
    my ($self, $handle, $msg) = @_;
    my ($cmd, $orig_cmd) = @{$msg}{qw/command orig_command/};
    my $prefix = $msg->{prefix};
    my $target = $msg->{target};
    my $param  = $msg->{params}[0];
    my $text   = $param && exists $CTCP_COMMAND_INFO{lc $param} ? $CTCP_COMMAND_INFO{lc $param}
                                                                : uc(join ' ', @CTCP_COMMAND_LIST);

    my $user = $handle->get_users_by_nicks($target);
    $self->send_ctcp_reply( $handle, $user, $cmd, ":$text" ) unless $msg->{silent};

    @_;
}

sub _event_ctcp_errmsg {}
sub _event_ctcp_ping {}
sub _event_ctcp_action {

}


# public function #

sub check_params {
    my ($self, $handle, $msg) = @_;
    return () unless $self && $handle;
    my $cmd   = $msg->{command};
    my $param = $msg->{params}[0];

    unless ($param) {
        $self->need_more_params($handle, $cmd);
        return ();
    }

    @_;
}

sub is_valid_channel_name { $_[0] =~ /$REGEX{channel}/; }

sub opt_parser { my %opt; $opt{$1} = $2 ? $2 : 1 while $_[0] =~ /(\w+)(?:=(\S+))?/g; %opt }

sub decorate_text {
    my ($text, $color) = @_;

    $color ne '' ? "\03$color$text\03" : $text;
}

sub replace_crlf {
    my $text = shift || return '';
    $text =~ s/[\r\n]+/ /g;

    $text;
}


# IrcGateway method #

# client to server
sub handle_irc_msg {
    my ($self, $handle, $raw, %opts) = @_;
    my $msg   = parse_irc_msg($raw);
    my $event = lc($msg->{command} || '');
       $event = exists $IRC_COMMAND_EVENT{"irc_$event"} ? "irc_$event" : 'irc';

    $self->logger->debug("handle_irc_msg: $raw, ".Dumper(\%opts));
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

    $self->logger->debug("handle_ctcp_msg: $raw, ".Dumper(\%opts));
    $msg->{raw} = $raw;
    $msg->{$_}  = $opts{$_} for keys %opts;
    $self->event($event, $handle => $msg);
}

# server to client
sub send_msg {
    my ($self, $handle, $cmd, @args) = @_;
    my $msg = mk_msg($self->to_prefix, $cmd, $handle->self->nick, @args);
    $self->logger->debug("send_msg: $msg");
    $handle->push_write($self->codec->encode($msg) . $CRLF);
}

sub send_cmd {
    my ($self, $handle, $user, $cmd, @args) = @_;
    my $prefix = ref $user eq 'Uc::IrcGateway::User' ? $user->to_prefix : $user;
    my $msg = mk_msg($prefix, $cmd, @args);
    $self->logger->debug("send_cmd: $msg");
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

# other method
sub to_prefix { $_[0]->host }

sub need_more_params {
    my ($self, $handle, $cmd) = @_;
    $self->send_msg($handle, ERR_NEEDMOREPARAMS, $cmd, 'Not enough parameters');
}

sub welcome_message {
    my ($self, $handle) = @_;
    $self->send_msg( $handle, RPL_WELCOME, $self->welcome );
    $self->send_msg( $handle, RPL_YOURHOST, "Your host is @{[ $self->servername ]} [@{[ $self->servername ]}/@{[ $self->port ]}]. @{[ ref $self ]}/$VERSION" );
    $self->send_msg( $handle, RPL_CREATED, "This server was created ".$self->ctime );
    $self->send_msg( $handle, RPL_MYINFO, "@{[ $self->servername ]} @{[ ref $self ]}-$VERSION" );

    $self->handle_irc_msg( $handle, 'MOTD' );
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
    return 1;
}



package Uc::IrcGateway::Channel;

use 5.010;
use common::sense;
use warnings qw(utf8);
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



package Uc::IrcGateway::Connection;

use 5.010;
use common::sense;
use warnings qw(utf8);
use Any::Moose;

use Carp;
use Path::Class;

=ignore
methods:
    HASHREF   = channels()
    CHANNELS  = get_channels( CHANNAME [, CHANNAME, ...] )
    CHANNELS  = set_channels( CHANNAME => CHANNEL [, CHANNAME => CHANNEL, ...] )
    CHANNEL   = del_channels( CHANNAME [, CHANNAME, ...] )
    BOOL      = has_channel( CHANNAME )
    CHANNAMES = channel_list()
    CHANNAMES = joined_channel_list( USERID )

properties:
    self     -> Uc::IrcGateway::User # connection's userdata
    channels -> { CHANNAME => Uc::IrcGateway::Channel } # hash of channels

options:
    same as AnyEvent::Handle

=cut

extends 'AnyEvent::Handle', any_moose('::Object');
# connection's user object
has 'self' => ( is => 'rw', isa => 'Uc::IrcGateway::User' );
# some options you need
has 'options' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
# DESTORY code
has 'on_destroy' => ( is => 'rw', isa => 'CodeRef' );
# channel list
has 'channels' => (
    is => 'rw', traits => ['Hash'], default => sub { {} }, init_arg => undef,
    isa => 'HashRef[Uc::IrcGateway::Channel]', handles => {
        get_channels => 'get',
        set_channels => 'set',
        del_channels => 'delete',
        has_channel  => 'defined',
        channel_list => 'keys',
} );
# login user list
has 'users' => (
    is => 'rw', traits => ['Hash'], default => sub { {} }, init_arg => undef,
    isa => 'HashRef[Uc::IrcGateway::User]', handles => {
        get_users => 'get',
        has_user  => 'defined',
        user_list => 'keys',
} );
# lookup (nick => login list)
has 'nicks' => (
    is => 'rw', traits => ['Hash'], default => sub { {} }, init_arg => undef,
    isa => 'HashRef', handles => {
        lookup     => 'get',
        set_lookup => 'set',
        del_lookup => 'delete',
        has_nick   => 'defined',
        nick_list  => 'keys',
} );

#__PACKAGE__->meta->make_immutable;
no Any::Moose;

sub new {
    my $class = shift;
    my $obj   = $class->SUPER::new( @_ );
    my $self  = $class->meta->new_object(
        __INSTANCE__ => $obj,
        @_,
    );
    while (my ($k, $v) = each %$obj) {
        $self->{$k} = $v;
    }

    return $self;
}

sub get_users_by_nicks {
    my $self = shift;
    my @user_list;
    push @user_list, $self->get_users($self->lookup($_ // '') // '') for @_;
    return @user_list;
}

sub set_users {
    my $self = shift;
    for my $user (@_) {
        croak "Arguments must be Uc::IrcGateway::User object" if not ref $user eq 'Uc::IrcGateway::User';
        $self->users->{$user->login} = $user;
        $self->set_lookup($user->nick, $user->login) if $user->registered;
    }

    wantarray ? @_ : scalar @_;
}

sub del_users {
    my $self = shift;
    my @del_users;
    for my $login (@_) {
        if ($self->has_user($login)) {
            my $user = delete $self->users->{$login};
            $self->del_lookup($user->nick);
            push @del_users, $user;
        }
    }

    wantarray ? @del_users : scalar @del_users;
}

sub who_is_channels {
    my ($self, $login) = @_;
    my @channels;
    # TODO: error if not $login

    for my $chan ($self->channel_list) {
        push @channels, $chan if $self->get_channels($chan)->has_user($login);
    }

    wantarray ? @channels : scalar @channels;
}

sub DESTROY {
    my $self = shift;
    my $ev = $self->on_destroy;
    $ev->($self) if ref $ev eq 'CODE';
    $self->SUPER::DESTROY();
}



package Uc::IrcGateway::User;

use 5.010;
use common::sense;
use warnings qw(utf8);
use Any::Moose;

=ignore
methods:
properties:
options:

=cut

# user properties
# nick     -> <nickname>
# login    -> <username>
# reakname -> <realname>
# host     -> <hostname>
# addr     -> addr at <hostname>
# server   -> <servername>
has [qw/nick login realname host addr server/] => ( is => 'rw', isa => 'Maybe[Str]', required => 1 );
# already registered flag
has 'registered' => ( is => 'rw', isa => 'Int', default => 0 );
# user mode
has 'mode' => ( is => 'ro', isa => 'HashRef', default => sub { {
    a => 0, # Away
    i => 0, # Invisible
    w => 0, # allow Wallops receiving
    r => 0, # allow Wallops receiving
    o => 0, # Operator flag
    O => 0, # local Operator flag
    s => 0, # allow Server notice receiving
} } );
# ctcp USERINFO message
has 'userinfo' => ( is => 'rw', isa => 'Maybe[Str]', default => '' );
# away message
has 'away_message' => ( is => 'rw', isa => 'Maybe[Str]', default => '' );
# for calc idle time
has 'last_modified' => ( is => 'rw', isa => 'Int', default => sub { time } );

__PACKAGE__->meta->make_immutable;
no Any::Moose;

sub to_prefix {
    return sprintf "%s!%s@%s", $_[0]->nick, $_[0]->login, $_[0]->host;
}

sub mode_string {
    my $mode = $_[0]->mode;
    return '+'.join '', grep { $mode->{$_} } sort keys %$mode;
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
