# vim: set ft=perl :
use utf8;
use strict;
use Test::More tests => 1;
use Test::TCP;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;
Uc::IrcGateway->load_components(qw/AutoRegisterUser/);
Uc::IrcGateway->load_plugins(qw/DefaultSet/);

use AnyEvent::IRC::Client ();
use AE ();

test_tcp(
    server => setup_ircd('Uc::IrcGateway'),
    client => sub {
        my $port = shift;
        my $cv = AE::cv;
        my $w  = AE::timer 60, 0, sub { fail('timeout'); $cv->send; };
        my $conn = AnyEvent::IRC::Client->new();

        $conn->reg_cb(
            registered => sub {
                ok 1, 'auto registered';
                $cv->send;
            },

            error => sub {
                my ($conn, $code, $message, $ircmsg) = @_;
                diag("$code: $message, ". explain $ircmsg) if $code != 422;
            },
        );
        $conn->connect(
            '127.0.0.1',
            $port,
            +{
                nick => 'testbot',
                user => 'testbot',
                real => 'test bot',
            },
        );
        $cv->recv;
    },
);

done_testing;
