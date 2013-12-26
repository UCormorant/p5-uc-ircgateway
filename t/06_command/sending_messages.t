# vim: set ft=perl :
use utf8;
use strict;
use Test::More tests => 13;
use Test::TCP;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;
Uc::IrcGateway->load_plugins(qw/DefaultSet AutoRegisterUser/);
Uc::IrcGateway->load_plugins(qw/+Mock::Plugin::SendingMessages/);

use AnyEvent::IRC::Client ();
use AE ();

test_tcp(
    server => setup_ircd('Uc::IrcGateway'),
    client => sub {
        my $port = shift;
        my $cv = AE::cv;
        my $w  = AE::timer 60, 0, sub { fail('timeout'); $cv->send; };
        my $conn = AnyEvent::IRC::Client->new();

        my @channels = split ",", my $channels = "#test1,#test2,#test3";
        my @nicks = split ",", my $nicks = "testnick1,testnick2,testnick3";
        $conn->reg_cb(
            registered => sub {
                ok 1, 'registered';
                $conn->send_srv('PRIVMSG', $channels, "privmsg to channel");
            },

            publicmsg => sub {
                my ($conn, $channel, $msg) = @_;
                ok scalar(grep { $_ eq $channel } @channels), "check channel message to $channel";

                @channels = grep { $_ ne $channel } @channels;

                if (not scalar @channels) {
                    $conn->send_srv('PRIVMSG', $nicks, "privmsg to user") if $msg->{command} eq 'PRIVMSG';
                    $conn->send_srv('NOTICE',  $nicks, "notice to user")  if $msg->{command} eq 'NOTICE';
                }
            },

            privatemsg => sub {
                my ($conn, $nick, $msg) = @_;
                ok scalar(grep { $_ eq $nick } @nicks), "check message to $nick";

                @nicks = grep { $_ ne $nick } @nicks;

                if (not scalar @nicks) {
                    if ($msg->{command} eq 'PRIVMSG') {
                        @channels = split ",", $channels;
                        @nicks = split ",", $nicks;
                        $conn->send_srv('NOTICE', $channels, "notice to channel");
                    }
                    $cv->send if $msg->{command} eq 'NOTICE';
                }
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
