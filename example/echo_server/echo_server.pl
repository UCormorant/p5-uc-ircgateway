#!/usr/local/bin/perl

use 5.014;
use common::sense;
use warnings qw(utf8);
use lib qw(lib ../../lib);
use EchoServer;

use Data::Lock qw(dlock);
dlock my $CHARSET = ($^O eq 'MSWin32' ? 'cp932' : 'utf8');
binmode STDIN  => ":encoding($CHARSET)";
binmode STDOUT => ":encoding($CHARSET)";

use opts;

local $| = 1;

opts my $host  => { isa => 'Str', default => '127.0.0.1' },
     my $port  => { isa => 'Int', default => '6667' },
     my $debug => { isa => 'Bool', default => 0 },
     my $help  => { isa => 'Bool', default => 0 };

warn <<"_HELP_" and exit if $help;
Usage: $0 --host=127.0.0.1 --port=6667 --debug
_HELP_

my $ircd = EchoServer->new(
    host => $host,
    port => $port,
    time_zone => 'Asia/Tokyo',
    debug => $debug,
);

$ircd->run();
AE::cv->recv();

1;
