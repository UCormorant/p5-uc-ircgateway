#!/usr/local/bin/perl

package EchoServer;

use 5.014;
use common::sense;
use warnings qw(utf8);

use lib qw(../lib);
use parent 'Uc::IrcGateway';

#extends 'Uc::IrcGateway';
#override '_event_irc_privmsg' => sub {
#    my ($self, $handle, $msg) = super();
#    return unless $self;
#
#    my ($msgtarget, $text) = @{$msg->{params}};
#
#    for my $target (@{$msg->{success}}) {
#        # send privmsg message to yourself
#        $self->send_cmd( $handle, $handle->self, 'PRIVMSG', $target, $text );
#    }
#
#    @_;
#};


package main;

use 5.014;
use common::sense;
use warnings qw(utf8);

use Readonly;
Readonly my $CHARSET => ($^O eq 'MSWin32' ? 'cp932' : 'utf8');
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
