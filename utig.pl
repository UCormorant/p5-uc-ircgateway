#!perl

use common::sense;
use warnings qw(utf8);

use Readonly;
Readonly my $CHARSET => 'cp932';
binmode STDIN  => ":encoding($CHARSET)";
binmode STDOUT => ":encoding($CHARSET)";
binmode STDERR => ":encoding($CHARSET)";

use lib qw(lib);
use Uc::IrcGateway::Twitter;
use Encode qw(decode find_encoding);
#use Encode::Guess qw(euc-jp shiftjis 7bit-jis); # using 'guess_encoding' is recoomended
use opts;
use Data::Dumper;
use Smart::Comments;

#BEGIN { $ENV{ANYEVENT_TWITTER_STREAM_SSL} = 1 }

local $| = 1;

opts my $host => { isa => 'Str', default => '127.0.0.1' },
     my $port => { isa => 'Int', default => '16668' },
     my $help => { isa => 'Int' };

warn <<"_HELP_" and exit if $help;
Usage: $0 --host=127.0.0.1 --port=16668
_HELP_

my $encode = find_encoding($CHARSET);

my $cv = AnyEvent->condvar;
my $ircd = Uc::IrcGateway::Twitter->new(
    host => $host,
    port => $port,
    servername => 'localhost',
    welcome => 'Welcome to the utig server',
    consumer_key    => '99tP2pSCdf7y0LkEKsMR5w',
    consumer_secret => 'eJiKJCAGnwolMDLgGaRyStHQvS5RBVCMGMZlAwk',
);

$ircd->run();
$cv->recv();


1;
