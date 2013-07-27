#!/usr/local/bin/perl

use 5.014;
use common::sense;
use warnings qw(utf8);
use lib qw(../../lib);

package EchoServer {
    no thanks;

    our $VERSION = Uc::IrcGateway->VERSION;

    use common::sense;
    use warnings qw(utf8);

    use parent 'Uc::IrcGateway';
    __PACKAGE__->load_plugins(qw/DefaultSet Echo Log::Notice4Handle/);
}

package EchoServer::Plugin::Echo {
    no thanks;

    use parent 'Class::Component::Plugin';
    use Uc::IrcGateway::Common;
    use Data::Dumper;

    sub echo :Hook('irc.privmsg.finish') {
        my ($hook, $self, $args) = @_;
        my ($handle, $msg, $plugin) = @$args;

        for my $res (@{$msg->{success}}) {
            # send privmsg message to yourself
            my $sender = $res->{target_is_user} ? $res->{target} : $handle->self->nick;
            my $target = $res->{target_is_user} ? $handle->self->nick : $res->{target};
            $self->send_cmd( $handle, $sender, 'PRIVMSG', $target, $res->{text} );
        }
    }
}

use EchoServer;

use Data::Lock qw(dlock);
dlock my $CHARSET = ($^O eq 'MSWin32' ? 'cp932' : 'utf8');
binmode STDIN  => ":encoding($CHARSET)";
binmode STDOUT => ":encoding($CHARSET)";

use opts;

local $| = 1;

opts my $host  => { isa => 'Str', default => '127.0.0.1' },
     my $port  => { isa => 'Int', default => '6667' },
     my $debug => { isa => 'Bool', default => 0 },
     my $help  => { isa => 'Bool', default => 0 };

warn <<"_HELP_" and exit if $help;
Usage: $0 --host=127.0.0.1 --port=6667 --debug
_HELP_

my $ircd = EchoServer->new(
    host => $host,
    port => $port,
    debug => $debug,
);

$ircd->run();
AE::cv->recv();

1;
