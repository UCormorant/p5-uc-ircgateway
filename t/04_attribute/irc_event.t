# vim: set ft=perl :
use utf8;
use strict;
use Test::More tests => 4;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;
Uc::IrcGateway->load_plugins(qw/+Mock::Plugin::IrcEventAttribute/);

my $ircd = new_ircd('Uc::IrcGateway');
my $irc_event = $ircd->event_irc_command;

subtest 'check events are registerd' => sub {
    ok exists $irc_event->{FOO}, 'FOO is registered';
    ok exists $irc_event->{BAR}, 'BAR is registered';
    ok exists $irc_event->{BAZ}, 'BAZ is registered';
};

subtest 'event FOO attributes' => sub {
    my $test = 'FOO';
    my $event = $irc_event->{$test};
    is ref $event->{code}, 'CODE', "$test code";
    is $event->{name}, "irc_event_$test", "$test event name";
    isa_ok $event->{plugin}, 'Mock::Plugin::IrcEventAttribute';
    is $event->{method}, "event_".lc $test, "$test method name";
    isa_ok ${$event->{guard}}, 'AnyEvent::Util::guard';
};

subtest 'event BAR attributes' => sub {
    my $test = 'BAR';
    my $event = $irc_event->{$test};
    is ref $event->{code}, 'CODE', "$test code";
    is $event->{name}, "irc_event_$test", "$test event name";
    isa_ok $event->{plugin}, 'Mock::Plugin::IrcEventAttribute';
    is $event->{method}, "event_".lc $test, "$test method name";
    isa_ok ${$event->{guard}}, 'AnyEvent::Util::guard';
};

subtest 'event BAZ attributes' => sub {
    my $test = 'BAZ';
    my $event = $irc_event->{$test};
    is ref $event->{code}, 'CODE', "$test code";
    is $event->{name}, "irc_event_$test", "$test event name";
    isa_ok $event->{plugin}, 'Mock::Plugin::IrcEventAttribute';
    is $event->{method}, "event_".lc $test, "$test method name";
    isa_ok ${$event->{guard}}, 'AnyEvent::Util::guard';
};

done_testing;
