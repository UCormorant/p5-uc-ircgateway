use utf8;
use strict;
use Test::More tests => 17;
use Test::TCP;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;
Uc::IrcGateway->load_plugins(qw/DefaultSet/);

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

        my $channels = "#test1,#test2,#test3,#test4";
        my @channels = split ",", $channels;
        my @list = ();
        my $part_channels = '#test1,#test2';
        my $join_channels = '#test3,#test4';
        $conn->reg_cb(
            registered => sub {
                ok 1, 'registered';
                $conn->send_srv('JOIN', $channels[0]);
                $conn->send_srv('JOIN', join ",", @channels[1..$#channels]);
            },

            join => sub {
                my ($conn, $nick, $channel, $is_myself) = @_;
                my $topic = "join $channel";
                ok 1, $topic;

                $conn->send_srv('TOPIC' => $channel, $topic);

                @channels = grep { $_ ne $channel } @channels;
                if (not scalar @channels) {
                    $conn->send_srv('LIST');
                }
            },

            channel_topic => sub {
                my ($conn, $channel, $topic, $who) = @_;
                is $topic, "join $channel", "check $channel topic";
            },

            irc_322 => sub { # RPL_LIST
                my ($conn, $msg) = @_;
                ok 1, "list $msg->{params}[1]";
                push @list, [@{$msg->{params}}[1,2]];
            },

            irc_323 => sub { # RPL_LISTEND
                my ($conn, $msg) = @_;
                is_deeply [map { $_->[0] } sort { $a->[0] cmp $b->[0] } @list], [split ",", $channels], "check channel list";

                @channels = split ",", $part_channels;
                $conn->send_srv('PART', $part_channels);
            },

            part => sub {
                my ($conn, $nick, $channel, $is_myself, $msg) = @_;
                ok 1, "$nick parts $channel";

                @channels = grep { $_ ne $channel } @channels;
                if (not scalar @channels) {
                    $cv->send;
                }
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
            },
        );
        $cv->recv;

        is_deeply [sort keys %{$conn->channel_list}], [split ",", $join_channels], "check join channel list";
    },
);

done_testing;
