# vim: set ft=perl :
use utf8;
use strict;
use Test::More tests => 6;
use Test::TCP;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;
Uc::IrcGateway->load_plugins(qw/DefaultSet AutoRegisterUser/);
Uc::IrcGateway->load_plugins(qw/+Mock::Plugin::OptionalFeatures/);

use AnyEvent::IRC::Client ();
use AE ();

test_tcp(
    server => setup_ircd('Uc::IrcGateway'),
    client => sub {
        my $port = shift;
        my $cv = AE::cv;
        my $w  = AE::timer 60, 0, sub { fail('timeout'); $cv->send; };
        my $conn = AnyEvent::IRC::Client->new();

        my @ison_query = qw(testbot hoge fuga piyo awaynick);
        my @ison_expect = qw(testbot awaynick);
        $conn->reg_cb(
            registered => sub {
                ok 1, 'registered';
                $conn->send_srv('ISON', @ison_query);
                $conn->send_srv('AWAY', 'Away message');
            },

            irc_303 => sub { # RPL_ISON
                my ($conn, $msg) = @_;
                is $msg->{params}[1], join(' ', @ison_expect), "check ison";
            },

            irc_306 => sub { # RPL_NOWAWAY
                ok 1, "check away enable";
                $conn->send_srv('AWAY');
            },

            irc_305 => sub { # RPL_UNAWAY
                ok 1, "check away disable";
                $conn->send_srv('PRIVMSG', 'awaynick', "privmsg.");
            },

            irc_301 => sub { # RPL_AWAY
                my ($conn, $msg) = @_;
                is $msg->{params}[1], 'awaynick', "check away target";
                is $msg->{params}[2], 'Gone.', "check away message";
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
                password => 'kogaidan',
            },
        );
        $cv->recv;
    },
);

done_testing;
