# vim: set ft=perl :
use utf8;
use strict;
use Test::More tests => 1;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;
Uc::IrcGateway->load_plugins(qw/+Mock::Plugin::LogLevelAttribute/);

my $ircd = new_ircd('Uc::IrcGateway');
my $log_level = $ircd->logger->log_level;

subtest 'check levels are registerd' => sub {
    plan tests => 4;
    ok exists $log_level->{low},    'low is registered';
    ok exists $log_level->{middle}, 'middle is registered';
    ok exists $log_level->{high},   'high is registered';
    ok exists $log_level->{any},    'any is registered';
};

done_testing;
