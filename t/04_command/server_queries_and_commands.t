# vim: set ft=perl :
use utf8;
use strict;
use Test::More;
use Test::TCP;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;
Uc::IrcGateway->load_plugins(qw/DefaultSet/);

use AnyEvent::IRC::Client ();
use AE ();
use Data::Dumper qw(Dumper);

SKIP: {
    skip "server commands are not implemented yet", 1;
test_tcp(
    server => setup_ircd('Uc::IrcGateway'),
    client => sub {
        my $port = shift;
        my $cv = AE::cv;
        my $w  = AE::timer 60, 0, sub { fail('timeout'); $cv->send; };
        my $conn = AnyEvent::IRC::Client->new();

        fail "do test!";
    },
);
}

done_testing;
