# vim: set ft=perl :
use utf8;
use strict;
use Test::More tests=> 1;
use Test::TCP;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;
Uc::IrcGateway->load_components(qw/AutoRegisterUser/);
Uc::IrcGateway->load_plugins(qw/DefaultSet/);

use AnyEvent::IRC::Client ();
use AE ();
use Encode qw(encode);
use Text::InflatedSprintf qw(inflated_sprintf);

my $motd_string = <<'_MOTD_';
テストMOTD
MOTDテスト
_MOTD_
chomp $motd_string;

my $mess = Uc::IrcGateway::Message->message_set->{RPL_MOTD};

my @RPL_MOTD = ();
my @RPL_MOTD_OK = map {
    my $line = join(' ', 'localhost', $mess->{number}, inflated_sprintf($mess->{format}, { text => $_ }));
    parse_irc_msg($line)->{params}[-1];
} split qr{$/}, encode('utf8', $motd_string);
my $START_MOTD = 0;

test_tcp(
    server => setup_ircd('Uc::IrcGateway', { motd_text => $motd_string }),
    client => sub {
        my $port = shift;
        my $cv = AE::cv;
        my $w  = AE::timer 60, 0, sub { fail('timeout'); $cv->send; };
        my $conn = AnyEvent::IRC::Client->new();

        $conn->reg_cb(
            registered => sub {
                $START_MOTD = 1;
                $conn->send_srv('MOTD');
            },

            irc_372 => sub {
                return unless $START_MOTD;
                my ($conn, $msg) = @_;
                push @RPL_MOTD, $msg->{params}[-1];
            },

            irc_376 => sub {
                return unless $START_MOTD;
                my ($conn, $msg) = @_;
                is_deeply \@RPL_MOTD, \@RPL_MOTD_OK, 'check MOTD messages';

                $cv->send;
            },

            error => sub {
                my ($conn, $code, $message, $ircmsg) = @_;
                if ($code == 422) {
                    fail("$code: $message, ". explain $ircmsg);
                    $cv->send; return;
                }
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
