#!perl

use common::sense;
use warnings qw(utf8);

use Readonly;
Readonly my $CHARSET => 'cp932';
binmode STDIN  => ":encoding($CHARSET)";
binmode STDOUT => ":encoding($CHARSET)";
binmode STDERR => ":encoding($CHARSET)";

use Encode qw(decode find_encoding);
#use Encode::Guess qw(euc-jp shiftjis 7bit-jis); # using 'guess_encoding' is recoomended
use opts;
use Data::Dumper;
use Smart::Comments;

#BEGIN { $ENV{ANYEVENT_TWITTER_STREAM_SSL} = 1 }

local $| = 1;

opts my $host => { isa => 'Str', default => '127.0.0.1' },
     my $port => { isa => 'Int', default => '16668' },
	 my $help => { isa => 'Int' };

warn <<"_HELP_" and exit if $help;
Usage: $0 --host=127.0.0.1 --port=16668
_HELP_

my $encode = find_encoding($CHARSET);

my $cv = AnyEvent->condvar;
my $ircd = Uc::TwitterIrcGateway->new(
	host => $host,
	port => $port,
	servername => 'localhost',
	welcome => 'Welcome to the utig server',
	consumer_key    => '99tP2pSCdf7y0LkEKsMR5w',
	consumer_secret => 'eJiKJCAGnwolMDLgGaRyStHQvS5RBVCMGMZlAwk',
);

$ircd->run();
$cv->recv();


BEGIN {
package Uc::TwitterIrcGateway;

use 5.010;
use common::sense;
use warnings qw(utf8);
use Encode qw(decode find_encoding);
use Any::Moose; # qw(::Util::TypeConstraints);
use Net::Twitter::Lite;
use AnyEvent::Twitter::Stream;
use AnyEvent::Handle;
use AnyEvent::Socket;
use AnyEvent::IRC::Util qw/parse_irc_msg mk_msg/;
use Sys::Hostname;
use Data::Dumper;
#use Smart::Comments;
use Config::Pit;

use Readonly;
Readonly my $CHARSET => 'utf8';

our $VERSION = '0.0.1';
our $CRLF = "\015\012";
my  $encode = find_encoding($CHARSET);

BEGIN {
	no strict 'refs';
	while (my ($code, $name) = each %AnyEvent::IRC::Util::RFC_NUMCODE_MAP) {
		*{"${name}"} = sub () { $code };
	}
};

extends 'Object::Event';


has 'host' => (
	is  => 'rw',
	isa => 'Str',
	required => 1,
	default => '127.0.0.1',
);

has 'port' => (
	is  => 'rw',
	isa => 'Int',
	required => 1,
	default => 6667,
);

has 'servername' => (
	is  => 'rw',
	isa => 'Str',
	required => 1,
	default => sub { hostname() },
);

has 'welcome' => (
	is  => 'rw',
	isa => 'Str',
	default => 'welcome to the utig server',
);

has 'conf_app' => (
	is  => 'rw',
	isa => 'HashRef',
	required => 1,
	default => sub {
		return pit_get('utig.pl');
	},
);

has 'ctime' => (
	is  => 'rw',
	isa => 'Str',
);

__PACKAGE__->meta->make_immutable;
no Any::Moose;


sub BUILD {
	my $self = shift;
	$self->reg_cb(
		nick => sub {
			my ($self, $msg, $handle) = @_;
			my $nick = shift @{$msg->{params}};

			unless ($nick) {
				$self->need_more_params($handle, 'NICK');
			}

			### $nick
			$handle->{conf_user} = pit_get("utig.pl.$nick") if $nick;

			twitter_agent($handle, $self->conf_app, $handle->{conf_user});
			$handle->{channels}->{'#twitter'} = {};
			$self->streamer(
				handle          => $handle,
				consumer_key    => $self->conf_app->{consumer_key},
				consumer_secret => $self->conf_app->{consumer_secret},
				token           => $handle->{conf_user}{token},
				token_secret    => $handle->{conf_user}{token_secret},
			);
		},
		user => sub {
			my ($self, $msg, $handle) = @_;
			my ($nick, $host, $server, $realname) = @{$msg->{params}};
			$handle->{nick}     = $nick;
			$handle->{host}     = $host;
			$handle->{server}   = $server;
			$handle->{realname} = $realname;

			$handle->{channels}->{'#twitter'} = { $handle->{conf_user}{user_id} => $handle->{nick} };
            $self->send_msg( $handle, RPL_WELCOME, $self->{welcome} );
            $self->send_msg( $handle, RPL_YOURHOST, "Your host is @{[ $self->servername ]} [@{[ $self->servername ]}/@{[ $self->port ]}]. @{[ ref $self ]}/$VERSION" ); # 002
            $self->send_msg( $handle, RPL_CREATED, "This server was created $self->{ctime}");
            $self->send_msg( $handle, RPL_MYINFO, "@{[ $self->servername ]} @{[ ref $self ]}-$VERSION" ); # 004
            $self->send_msg( $handle, ERR_NOMOTD, "MOTD File is missing" );

			$self->handle_msg(parse_irc_msg('JOIN #twitter'), $handle);
		},
		join => sub {
			my ($self, $msg, $handle) = @_;
			my $chans = shift @{$msg->{params}};
			my $nick = $handle->{nick};

			unless ($chans) {
				$self->need_more_params($handle, 'JOIN');
			}

			for my $chan (split /,/, $chans) {
				my $raw;
				$handle->{channels}->{$chan}->{$handle->{conf_user}{user_id}} = $nick;

				# sever reply
				$self->send_msg( $handle, RPL_TOPIC, $chan,  $handle->{topics}->{$chan} || '' );
				$self->send_msg( $handle, RPL_NAMREPLY, $chan, "duke" ); # TODO
				$raw = mk_msg($self->servername, 'MODE', $chan, '+o', $nick) . $CRLF;
				### $raw
				$handle->push_write($raw);

				# send join message
				my $comment = sprintf("%s!%s@%s", $nick, $nick, $self->servername);
				$raw = mk_msg($comment, 'JOIN', $chan) . $CRLF;
				### $raw
				$handle->push_write($raw);
			}
		},
		part => sub {
			my ($self, $msg, $handle) = @_;
			my ($chans, $text) = @{$msg->{params}};
			my $nick = $handle->{nick};

			unless ($chans) {
				$self->need_more_params($handle, 'JOIN');
			}

			for my $chan (split /,/, $chans) {
				delete $handle->{channels}->{$chan}->{$handle->{conf_user}{user_id}};

				# send part message
				my $comment = sprintf("%s!%s@%s", $nick, $nick, $self->servername);
				my $raw = mk_msg($comment, 'PART', $chan, $text) . $CRLF;
				### $raw
				$handle->push_write($raw);
			}
		},
		topic => sub {
			my ($self, $msg, $handle) = @_;
			my ($chan, $topic) = @{$msg->{params}};
			my $nick = $handle->{nick};

			unless ($chan) {
				$self->need_more_params($handle, 'TOPIC');
			}

			if ($topic) {
				$handle->{topics}->{$chan} = $topic;
				$self->send_msg($handle, RPL_TOPIC, $chan, $topic);
			}
			else {
				$self->send_msg($handle, RPL_NOTOPIC, $chan, 'No topic is set');
			}
		},
		privmsg => sub {
			my ($self, $msg, $handle) = @_;
			my ($chan, $text) = @{$msg->{params}};
			my $nick = $handle->{nick};

			unless ($chan) {
				$self->need_more_params($handle, 'PRIVMSG');
			}

			eval { twitter_agent($handle)->update($encode->decode($text)); };
			unless ($@) {
			}
			else {
				$self->send_msg($handle, RPL_NOTOPIC, $chan, 'send error: ' . $text);
			}
		},
		notice => sub {
			my ($self, $msg, $handle) = @_;
			my ($chan, $text) = @{$msg->{params}};
			my $nick = $handle->{nick};
			unless ($chan) {
				$self->need_more_params($handle, 'NOTICE');
			}
			# no reply any message
		},
		list => sub {
			my ($self, $msg, $handle) = @_;
			my $chans = shift @{$msg->{params}};
			my $nick = $handle->{nick};
			$self->list($handle, $chans);
		},
		who => sub {
			my ($self, $msg, $handle) = @_;
			my $chans = shift @{$msg->{params}};
			my $nick = $handle->{nick};
			unless ($chans) {
				$self->need_more_params($handle, 'WHO');
			}
			while (my ($k, $v) = each %{$handle->{channels}{$chans}}) {
				$self->send_msg( $handle, RPL_WHOREPLY, $chans, $v, $k, $k, $v, "H :1", $k);
			}
			$self->send_msg( $handle, RPL_ENDOFWHO, 'END of /WHO List');
		},
		quit => sub {
			my ($self, $msg, $handle) = @_;
			undef $handle->{streamer};
			undef $handle;
		},
		on_eof => sub {
			my ($self, $handle) = @_;
			undef $handle;
		},
	);
}

sub run {
	my $self = shift;
	$self->ctime(scalar(localtime));
	tcp_server $self->host, $self->port, sub {
		my ($fh, $host, $port) = @_;
		my $handle = AnyEvent::Handle->new(fh => $fh,
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

sub handle_msg {
	my ($self, $msg, $handle) = @_;
	my $event = lc($msg->{command});
	   $event =~ s/^(\d+)$/irc_$1/g;
	$self->event($event, $msg, $handle);
}

sub _server_comment {
	my ($self, $nick) = @_;
	return sprintf '%s!~%s@%s', $nick, $nick, $self->servername;
}

sub list {
	my ($self, $handle, $chans) = @_;
	my $nick = $handle->{nick};
	my $comment = $self->_server_comment($nick);
	my $send = sub {
		my $msg = mk_msg($comment, @_) . $CRLF;
		$handle->push_write($msg);
	};
	my $send_rpl_list = sub {
		my $chan = shift;
		$send->(RPL_LIST, $nick, $chan, scalar values %{$handle->{channels}{$chan}}, (":$handle->{topics}{$chan}" || ''));
	};
	$send->(RPL_LISTSTART, $nick, 'Channel', ':Users', 'Name');
	$chans = join ',', sort keys %{$handle->{channels}} if !$chans;
	for my $chan (split /,/, $chans) {
		$send_rpl_list->($chan);
	}
	$send->(RPL_LISTEND, '$nick', 'END of /List');
}

sub send_msg {
	my ($self, $handle, $cmd, @args) = @_;
	my $msg = mk_msg($self->host, $cmd, $handle->{nick}, @args) . $CRLF;
	### $msg
	$handle->push_write($msg);
}

sub need_more_params {
	my ($self, $handle, $cmd) = @_;
	$self->send_msg($handle, ERR_NEEDMOREPARAMS, $cmd, 'Not enough parameters');
}

sub twitter_agent {
	my ($handle, $conf_app, $conf_user) = @_;
	return $handle->{nt} if ref $handle->{nt} eq 'Net::Twitter::Lite';

	my $nt = Net::Twitter::Lite->new(%$conf_app);
	$nt->access_token($conf_user->{token});
	$nt->access_token_secret($conf_user->{token_secret});

	my ($pin, @userdata);
	while (!$nt->authorized()) {
		say 'please open the following url and allow this app, then enter PIN code.';
		say $nt->get_authorization_url();
		print 'PIN: '; chomp($pin = <STDIN>);

		@{$conf_user}{qw/token token_secret user_id screen_name/} = $nt->request_access_token(verifier => $pin);
		$nt->{config_updated} = 1;
	}

	return $handle->{nt} = $nt;
}

sub streamer {
	my ($self, %config) = @_;
	my $handle = delete $config{handle};
	return $handle->{streamer} if exists $handle->{streamer};
	$handle->{streamer} = AnyEvent::Twitter::Stream->new(
		method  => 'userstream',
		timeout => 45,
		%config,

		on_connect => sub {
			my $comment = sprintf("%s!%s@%s", 'twitterircgateway', 'twitterircgateway', $self->servername);
			my $raw = mk_msg($comment, 'NOTICE', '#twitter', 'streamer start to read.' ) . $CRLF;
			$handle->push_write($raw);
		},
		on_tweet => sub {
			my $tweet = shift;
			my $nick = $tweet->{user}{screen_name};
			return unless $nick and $tweet->{text};

			(my $text = $encode->encode($tweet->{text})) =~ s/[\r\n]+/ /g;
			if (exists $handle->{channels}{'#twitter'} and exists $tweet->{user}{id}) {
				if (not exists $handle->{channels}{'#twitter'}{$tweet->{user}{id}}) {
					my $raw = mk_msg($nick, 'JOIN', '#twitter') . $CRLF;
					### $raw
					$handle->push_write($raw);
					$handle->{channels}{'#twitter'}{$tweet->{user}{id}} = $nick;
				}
			    elsif ($handle->{channels}{'#twitter'}{$tweet->{user}{id}} ne $nick) {
					my $raw = mk_msg($handle->{channels}{'#twitter'}{$tweet->{user}{id}}, 'NICK', $nick) . $CRLF;
					### $raw
					$handle->push_write($raw);
					$handle->{channels}{'#twitter'}{$tweet->{user}{id}} = $nick;
				}
				if ($nick eq $handle->{nick}) {
					$handle->{topics}->{'#twittter'} = $text;
					$self->send_msg($handle, RPL_TOPIC, '#twitter', $text);
					return;
				}
				else {
					my $comment = sprintf("%s!%s@%s", $nick, $nick, $self->servername);
					my $raw = mk_msg($comment, 'PRIVMSG', '#twitter', $text ) . $CRLF;
					# $raw
					$handle->push_write($raw);
				}
			}
		},
		on_error => sub {
			warn "error: $_[0]";
			#		undef $streamer;
		},
		on_eof => sub {
			my $comment = sprintf("%s!%s@%s", 'twitterircgateway', 'twitterircgateway', $self->servername);
			my $raw = mk_msg($comment, 'NOTICE', '#twitter', 'streamer stop to read.' ) . $CRLF;
			$handle->push_write($raw);
		},
	);
}


}
1;
__END__
