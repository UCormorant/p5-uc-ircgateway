# vim: set ft=perl :
use utf8;
use strict;
use Test::More tests => 9;
use Test::TCP;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;
Uc::IrcGateway->load_components(qw/AutoRegisterUser/);
Uc::IrcGateway->load_plugins(qw/DefaultSet/);
Uc::IrcGateway->load_plugins(qw/+Mock::Plugin::UserBasedQueries/);

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

        my $count = 2;
        $cv->begin for 1..2;
        $conn->reg_cb(
            registered => sub {
                ok 1, 'registered';
                $conn->send_srv('WHO', '#channel');
                $conn->send_srv('WHO', 'nick');
                $conn->send_srv('WHOIS', 'nick');
            },

            irc_352 => sub { # RPL_WHOREPLY
                my ($conn, $msg) = @_;
                ok 1, "who reply";
            },

            irc_315 => sub { # RPL_ENDOFWHO
                my ($conn, $msg) = @_;
                ok 1, "end of who";
                $cv->end unless --$count;
            },

            irc_311 => sub { # RPL_WHOISUSER
                my ($conn, $msg) = @_;
                ok 1, "whois user";
            },

            irc_312 => sub { # RPL_WHOISSERVER
                my ($conn, $msg) = @_;
                ok 1, "whois server";
            },

            irc_317 => sub { # RPL_WHOISIDLE
                my ($conn, $msg) = @_;
                ok 1, "whois idle";
            },

            irc_318 => sub { # RPL_ENDOFWHOIS
                my ($conn, $msg) = @_;
                ok 1, "end of whois";
                $cv->end;
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
                password => 'kogaidan',
            },
        );
        $cv->recv;
    },
);

done_testing;
