# vim: set ft=perl :
use utf8;
use strict;
use Test::More tests => 5;
use Test::TCP;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;
Uc::IrcGateway->load_plugins(qw/DefaultSet/);
Uc::IrcGateway->load_plugins(qw/+Mock::Plugin::ConnectionRegistration/);

use AnyEvent::IRC::Client ();
use AE ();
use Data::Dumper qw(Dumper);

test_tcp(
    server => setup_ircd('Uc::IrcGateway'),
    client => sub {
        my $port = shift;
        my $cv = AE::cv;
        my $w  = AE::timer 60, 0, sub { fail('timeout'); $cv->send; };
        my $conn = AnyEvent::IRC::Client->new();

        $cv->begin for 1..5;
        $conn->reg_cb(
            irc_001 => sub {
                ok 1, 'irc_001 RPL_WELCOME';
                $cv->end();
            },
            irc_002 => sub {
                ok 1, 'irc_002 RPL_YOURHOST';
                $cv->end();
            },
            irc_003 => sub {
                ok 1, 'irc_003 RPL_CREATED';
                $cv->end();
            },
            irc_004 => sub {
                ok 1, 'irc_004 RPL_MYINFO';
                $cv->end();
            },
            registered => sub {
                ok 1, 'registered';
                $cv->end();
            },
            error => sub {
                my ($conn, $code, $message, $ircmsg) = @_;
                diag("$code: $message, ". Dumper($ircmsg)) if $code != 422;
            },
        );
        $conn->connect(
            '127.0.0.1',
            $port,
            +{
                nick => 'testbot',
                user => 'testbot',
                real => 'test bot',
                password => 'kogaidan',
            },
        );
        $cv->recv;
    },
);

done_testing;
