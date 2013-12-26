# vim: set ft=perl :
use utf8;
use strict;
use Test::More tests => 34;
use Test::TCP;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;
Uc::IrcGateway->load_plugins(qw/DefaultSet AutoRegisterUser/);
Uc::IrcGateway->load_plugins(qw/+Mock::Plugin::ChannelOperation/);

use AnyEvent::IRC::Client ();
use AE ();

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
        my $invite_nicks = 'hoge,fuga,piyo';
        my $kick_nicks = 'hoge,fuga';
        my $kick_channels = '#test2,#test3';
        my $channels_member_count = '4,2,2,4';
        my $part_channels = '#test1,#test2';
        my $joined_channels = '#test3,#test4';
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

                if ($is_myself) {
                    $conn->send_srv('TOPIC' => $channel, $topic);

                    @channels = grep { $_ ne $channel } @channels;
                    if (not scalar @channels) {
                        for my $chan (split ",", $channels) {
                            $conn->send_srv('INVITE', $_, $chan) for split ",", $invite_nicks;
                        }
                        $conn->send_srv('KICK', $kick_channels, $kick_nicks, "kick message.");
                        $conn->send_srv('LIST');
                    }
                }
            },

            channel_topic => sub {
                my ($conn, $channel, $topic, $who) = @_;
                is $topic, "join $channel", "check $channel topic";
            },

            irc_341 => sub { # RPL_INVITING
                my ($conn, $msg) = @_;
                ok 1, "invite $msg->{params}[2] to $msg->{params}[1]";
            },

            kick => sub {
                my ($conn, $kicked_nick, $channel, $is_myself, $msg, $kicker_nick) = @_;
                my $kick_nicks_reg = $kick_nicks =~ s/,/|/gr;
                my $kick_channels_reg = $kick_channels =~ s/,/|/gr;
                like "$kicked_nick kicked from $channel by $kicker_nick: $msg",
                     qr{(?:$kick_nicks_reg) kicked from (?:$kick_channels_reg) by testbot: kick message\.},
                     "$kicked_nick kicked from $channel";
            },

            irc_322 => sub { # RPL_LIST
                my ($conn, $msg) = @_;
                is $msg->{params}[3], "join $msg->{params}[1]", "list $msg->{params}[1]";
                push @list, [@{$msg->{params}}[1,2]];
            },

            irc_323 => sub { # RPL_LISTEND
                my ($conn, $msg) = @_;
                my @list_channel = sort { $a->[0] cmp $b->[0] } @list;
                is_deeply [map { $_->[0] } @list_channel], [split ",", $channels], "check channel list";
                is_deeply [map { $_->[1] } @list_channel], [split ",", $channels_member_count], "check channel member count";

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

        is_deeply [sort keys %{$conn->channel_list}], [split ",", $joined_channels], "check join channel list";
    },
);

done_testing;
