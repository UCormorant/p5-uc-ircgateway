use utf8;
use strict;
use Test::Base::Less;
use Test::TCP;
use Test::Difflet qw(is_deeply);

plan tests => 163;

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;

use AE ();
use AnyEvent::Util qw(fh_nonblocking);
use AnyEvent::IRC::Util qw(mk_msg);
use Text::InflatedSprintf qw(inflated_sprintf);

my $ircd = new_ircd('Uc::IrcGateway', {
    host => '127.0.0.1',
    message_set => Uc::IrcGateway::Message->message_set,
});
my $user = Uc::IrcGateway::TempUser->new(nick => 'testnick');

open my($fh), '+>', file($ircd->app_dir, 'handle.pid');
fh_nonblocking $fh, 1;

filters {
    input    => ['eval'],
    expected => ['trim'],
};

run {
    my $block = shift;
    my $name = $block->name;
    my $set  = $ircd->message_set->{$name};
    my $data = { response => $block->input };

    is($block->number, $set->{number}, "$name number");

    seek $fh, 0, 0;
    truncate $fh, 0;

    eval {
        my $cv_handle = AE::cv;
        my $handle = Uc::IrcGateway::Connection->new( fh => $fh );
        $handle->self($user);

        $ircd->send_reply( $handle, $data, $name );

        $handle->on_drain(sub { $cv_handle->send });
        $cv_handle->recv;
    };
    if ($@) {
        !$block->expected
            ? pass("Unused")
            : fail("send_reply error: $@");
    }
    else {
        seek $fh, 0, 0;
        my $got = do { local $/; $ircd->codec->decode($fh->getline) =~ s/\015\012/\n/gr; };

        is($got, $block->expected, "$name format");
    }
};

done_testing;


__DATA__

=== RPL_WELCOME
--- number: 001
--- input
+{
    nick => 'testnick',
    user => 'testuser',
    host => 'testhost',
}
--- expected
:127.0.0.1 001 testnick Welcome to the Internet Relay Network, testnick!testuser@testhost

=== RPL_YOURHOST
--- number: 002
--- input
+{
    servername => 'test.server',
    version    => 'IRC/testversion',
}
--- expected
:127.0.0.1 002 testnick Your host is test.server, running version IRC/testversion

=== RPL_CREATED
--- number: 003
--- input
+{
    date => 'Sat Jul 13 01:54:53 2013',
}
--- expected
:127.0.0.1 003 testnick This server was created Sat Jul 13 01:54:53 2013

=== RPL_MYINFO
--- number: 004
--- input
+{
    servername => 'test.server',
    version    => 'IRC/testversion',
    available_user_modes => '*',
    available_channel_modes => '*',
}
--- expected
:127.0.0.1 004 testnick test.server IRC/testversion *, *

=== RPL_BOUNCE
--- number: 005
--- input
+{
    servername => 'test.server',
    port => 6667,
}
--- expected
:127.0.0.1 005 testnick Try server test.server, port 6667

=== RPL_USERHOST
--- number: 302
--- input
+{
    reply => [qw/nick=+~nick@host.name nick2=+~nick2@host.name/],
}
--- expected
:127.0.0.1 302 testnick :nick=+~nick@host.name nick2=+~nick2@host.name

=== RPL_ISON
--- number: 303
--- input
+{
    nick => [qw/nick nick2 nick3 nick4/],
}
--- expected
:127.0.0.1 303 testnick :nick nick2 nick3 nick4

=== RPL_AWAY
--- number: 301
--- input
+{
    nick => 'nick',
    away_message => 'away',
}
--- expected
:127.0.0.1 301 testnick nick away

=== RPL_UNAWAY
--- number: 305
--- input
+{}
--- expected
:127.0.0.1 305 testnick :You are no longer marked as being away

=== RPL_NOWAWAY
--- number: 306
--- input
+{}
--- expected
:127.0.0.1 306 testnick :You have been marked as being away

=== RPL_WHOISUSER
--- number: 311
--- input
+{
    nick => 'nick',
    user => 'user',
    host => 'host.name',
    realname => 'real name',
}
--- expected
:127.0.0.1 311 testnick nick user host.name * :real name

=== RPL_WHOISSERVER
--- number: 312
--- input
+{
    nick => 'nick',
    server => 'server.name',
    server_info => 'IRC Server(TM)'
}
--- expected
:127.0.0.1 312 testnick nick server.name :IRC Server(TM)

=== RPL_WHOISOPERATOR
--- number: 313
--- input
+{
    nick => 'nick',
}
--- expected
:127.0.0.1 313 testnick nick :is an IRC operator

=== RPL_WHOISIDLE
--- number: 317
--- input
+{
    nick => 'nick',
    idle => 180,
}
--- expected
:127.0.0.1 317 testnick nick 180 :seconds idle

=== RPL_ENDOFWHOIS
--- number: 318
--- input
+{
    nick => 'nick',
}
--- expected
:127.0.0.1 318 testnick nick :End of WHOIS list

=== RPL_WHOISCHANNELS
--- number: 319
--- input
+{
    nick => 'nick',
    user_state => ['', '@', '+'],
    channel => [qw/#chan1 #chan2 #chan3/]
}
--- expected
:127.0.0.1 319 testnick nick :#chan1 @#chan2 +#chan3

=== RPL_WHOISCHANNELS
--- number: 319
--- input
+{
    nick => 'nick',
    user_state => [('', '@', '+') x 50],
    channel => [qw/#chan1 #chan2 #chan3/ x 50]
}
--- expected
:127.0.0.1 319 testnick nick :#chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2
:127.0.0.1 319 testnick nick :+#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1
:127.0.0.1 319 testnick nick :@#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3 #chan1 @#chan2 +#chan3

=== RPL_WHOWASUSER
--- number: 314
--- input
+{
    nick => 'nick',
    user => 'user',
    host => 'host.name',
    realname => 'real name',
}
--- expected
:127.0.0.1 314 testnick nick user host.name * :real name

=== RPL_ENDOFWHOWAS
--- number: 369
--- input
+{
    nick => 'nick',
}
--- expected
:127.0.0.1 369 testnick nick :End of WHOWAS

=== RPL_LISTSTART
--- number: 321
--- input
+{
    nick => 'nick',
}
--- expected
:127.0.0.1 321 testnick nick Channel :Users Name

=== RPL_LIST
--- number: 322
--- input
+{
    channel => '#channel',
    visible => '3',
    topic => 'channel topic',
}
--- expected
:127.0.0.1 322 testnick #channel 3 :channel topic

=== RPL_LISTEND
--- number: 323
--- input
+{}
--- expected
:127.0.0.1 323 testnick :End of LIST

=== RPL_UNIQOPIS
--- number: 325
--- input
+{
    channel => '#channel',
    nick => 'nick',
}
--- expected
:127.0.0.1 325 testnick #channel nick

=== RPL_CHANNELMODEIS
--- number: 324
--- input
+{
    channel => '#channel',
    mode => '+klns',
    mode_params => 'hogefuga 2',
}
--- expected
:127.0.0.1 324 testnick #channel +klns hogefuga 2

=== RPL_NOTOPIC
--- number: 331
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 331 testnick #channel :No topic is set.

=== RPL_TOPIC
--- number: 332
--- input
+{
    channel => '#channel',
    topic => 'channel topic',
}
--- expected
:127.0.0.1 332 testnick #channel :channel topic

=== RPL_INVITING
--- number: 341
--- input
+{
    channel => '#channel',
    nick => 'nick'
}
--- expected
:127.0.0.1 341 testnick #channel nick

=== RPL_SUMMONING
--- number: 342
--- input
+{
    user => 'user',
}
--- expected
:127.0.0.1 342 testnick user :Summoning user to IRC

=== RPL_INVITELIST
--- number: 346
--- input
+{
    channel => '#channel',
    invitemask => '*~*@*.jp',
}
--- expected
:127.0.0.1 346 testnick #channel *~*@*.jp

=== RPL_ENDOFINVITELIST
--- number: 347
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 347 testnick #channel :End of channel invite list

=== RPL_EXCEPTLIST
--- number: 348
--- input
+{
    channel => '#channel',
    exceptionmask => '*~*@*.jp',
}
--- expected
:127.0.0.1 348 testnick #channel *~*@*.jp

=== RPL_ENDOFEXCEPTLIST
--- number: 349
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 349 testnick #channel :End of channel exception list

=== RPL_VERSION
--- number: 351
--- input
+{
    version => '0.0.1',
    debug_level => '5',
    server => 'server.name',
    comments => 'hi there.',
}
--- expected
:127.0.0.1 351 testnick 0.0.1.5 server.name :hi there.

=== RPL_WHOREPLY
--- number: 352
--- input
+{
    channel => '#channel',
    nick => 'nick',
    user => 'user',
    host => 'host.name',
    realname => 'real name',
    server => 'server.name',
    user_state => 'H*',
    hopcount => 2,
}
--- expected
:127.0.0.1 352 testnick #channel user host.name server.name nick H* :2 real name

=== RPL_ENDOFWHO
--- number: 315
--- input
+{
    name => '#channel',
}
--- expected
:127.0.0.1 315 testnick #channel :End of WHO list

=== RPL_NAMREPLY
--- number: 353
--- input
+{
    channel_mode => '=',
    channel => '#channel',
    user_state => ['', '@', '+'],
    nick => [qw/nick1 nick2 nick3/],
}
--- expected
:127.0.0.1 353 testnick = #channel :nick1 @nick2 +nick3

=== RPL_NAMREPLY
--- number: 353
--- input
+{
    channel_mode => '=',
    channel => '#channel',
    user_state => [('', '@', '+') x 50],
    nick => [qw/nick1 nick2 nick3/ x 50],
}
--- expected
:127.0.0.1 353 testnick = #channel :nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2
:127.0.0.1 353 testnick = #channel :+nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1 @nick2 +nick3 nick1
:127.0.0.1 353 testnick = #channel :@nick2 +nick3

=== RPL_ENDOFNAMES
--- number: 366
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 366 testnick #channel :End of NAMES list

=== RPL_LINKS
--- number: 364
--- input
+{
    mask => '*',
    server => 'server.name',
    hopcount => 2,
    server_info => 'server info',
}
--- expected
:127.0.0.1 364 testnick * server.name :2 server info

=== RPL_ENDOFLINKS
--- number: 365
--- input
+{
    mask => '*',
}
--- expected
:127.0.0.1 365 testnick * :End of LINKS list

=== RPL_BANLIST
--- number: 367
--- input
+{
    channel => '#channel',
    banmask => '*',
}
--- expected
:127.0.0.1 367 testnick #channel *

=== RPL_ENDOFBANLIST
--- number: 368
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 368 testnick #channel :End of channel ban list

=== RPL_INFO
--- number: 371
--- input
+{
    string => 'Birth Date: Sat Feb 26 2011 at 14:35:19 JST, compile # 1',
}
--- expected
:127.0.0.1 371 testnick :Birth Date: Sat Feb 26 2011 at 14:35:19 JST, compile # 1

=== RPL_ENDOFINFO
--- number: 374
--- input
+{}
--- expected
:127.0.0.1 374 testnick :End of INFO list

=== RPL_MOTDSTART
--- number: 375
--- input
+{
    server => 'server.name',
}
--- expected
:127.0.0.1 375 testnick :- server.name Message of the day -

=== RPL_MOTD
--- number: 372
--- input
+{
    text => 'message of the day.',
}
--- expected
:127.0.0.1 372 testnick :- message of the day.

=== RPL_ENDOFMOTD
--- number: 376
--- input
+{}
--- expected
:127.0.0.1 376 testnick :End of MOTD command

=== RPL_YOUREOPER
--- number: 381
--- input
+{}
--- expected
:127.0.0.1 381 testnick :You are now an IRC operator

=== RPL_REHASHING
--- number: 382
--- input
+{
    config_file => 'configure.ini',
}
--- expected
:127.0.0.1 382 testnick configure.ini Rehashing

=== RPL_YOURESERVICE
--- number: 383
--- input
+{
    servicename => 'Service name',
}
--- expected
:127.0.0.1 383 testnick You are service Service name

=== RPL_TIME
--- number: 391
--- input
+{
    server => 'server.name',
    local_time => 'Tuesday July 23 2013 -- 18:00 +09:00',
}
--- expected
:127.0.0.1 391 testnick server.name :Tuesday July 23 2013 -- 18:00 +09:00

=== RPL_USERSSTART
--- number: 392
--- input
+{}
--- expected
:127.0.0.1 392 testnick :UserID   Terminal  Host

=== RPL_USERS
--- number: 393
--- input
+{
    username => 'user',
    ttyline => 'ttyline',
    hostname => 'host.name',
}
--- expected
:127.0.0.1 393 testnick :user ttyline host.name

=== RPL_ENDOFUSERS
--- number: 394
--- input
+{}
--- expected
:127.0.0.1 394 testnick :End of users

=== RPL_NOUSERS
--- number: 395
--- input
+{}
--- expected
:127.0.0.1 395 testnick :Nobody logged in

=== RPL_TRACELINK
--- number: 200
--- input
+{
    version_and_debug_level => '1.2.3-4',
    destination => '0',
    next_server => '0',
    protocol_version => '0',
    link_uptime_in_seconds => '0',
    backstream_sendq => '0',
    upstream_sendq => '0',
}
--- expected
:127.0.0.1 200 testnick Link 1.2.3-4 0, 0 V0 0 0 0

=== RPL_TRACECONNECTING
--- number: 201
--- input
+{
    class => '',
    server => 'test.server',
}
--- expected
:127.0.0.1 201 testnick Try.  test.server

=== RPL_TRACEHANDSHAKE
--- number: 202
--- input
+{
    class => '',
    server => 'test.server',
}
--- expected
:127.0.0.1 202 testnick H.S.  test.server

=== RPL_TRACEUNKNOWN
--- number: 203
--- input
+{
    class => '',
    client_ip_address => '192.168.0.1',
}
--- expected
:127.0.0.1 203 testnick ????  [192.168.0.1]

=== RPL_TRACEOPERATOR
--- number: 204
--- input
+{
    class => '',
    nick => 'nick',
}
--- expected
:127.0.0.1 204 testnick Oper  nick

=== RPL_TRACEUSER
--- number: 205
--- input
+{
    class => '',
    nick => 'nick',
}
--- expected
:127.0.0.1 205 testnick User  nick

=== RPL_TRACESERVER
--- number: 206
--- input
+{
    class => '',
    int => '1',
    server => 'server',
    nick => 'nick',
    user => 'user',
    host => 'host',
    protocol_version => '',
}
--- expected
:127.0.0.1 206 testnick Serv  1S 1C server, nick!user@host V

=== RPL_TRACESERVICE
--- number: 207
--- input
+{
    class => '',
    name => 'name',
    type => 'type',
    active_type => '',
}
--- expected
:127.0.0.1 207 testnick Service  name type

=== RPL_TRACENEWTYPE
--- number: 208
--- input
+{
    newtype => 'newtype',
    client_name => 'client',
}
--- expected
:127.0.0.1 208 testnick newtype 0 client

=== RPL_TRACECLASS
--- number: 209
--- input
+{
    class => '',
    count => '5',
}
--- expected
:127.0.0.1 209 testnick Class  5

=== RPL_TRACERECONNECT
--- number: 210
--- input
+{
}
--- expected

=== RPL_TRACELOG
--- number: 261
--- input
+{
    logfile => 'logfile.log',
    debug_level => '5',
}
--- expected
:127.0.0.1 261 testnick File logfile.log 5

=== RPL_TRACEEND
--- number: 262
--- input
+{
    servername => 'server.name',
    version => '0.0.1',
    debug_level => '5',
}
--- expected
:127.0.0.1 262 testnick server.name 0.0.1.5 :End of TRACE

=== RPL_STATSLINKINFO
--- number: 211
--- input
+{
    linkname => '0',
    sendq => '0',
    sent_messages => '0',
    sent_Kbytes => '0',
    received_messages => '0',
    received_Kbytes => '0',
    time_open => '0',
}
--- expected
:127.0.0.1 211 testnick 0 0 0, 0 0 0 0

=== RPL_STATSCOMMANDS
--- number: 212
--- input
+{
    command => 'NICK',
    count => '100',
    byte_count => '1000',
    remote_count => '1000',
}
--- expected
:127.0.0.1 212 testnick NICK 100 1000 1000

=== RPL_ENDOFSTATS
--- number: 219
--- input
+{
    stats_letter => '',
}
--- expected
:127.0.0.1 219 testnick  :End of STATS report

=== RPL_STATSUPTIME
--- number: 242
--- input
+{
    day => 10,
    hour => 10,
    min => 1,
    sec => 1,
}
--- expected
:127.0.0.1 242 testnick :Server Up 10 days 10:01:01

=== RPL_STATSOLINE
--- number: 243
--- input
+{
    hostmask => '*',
    name => 'name',
}
--- expected
:127.0.0.1 243 testnick O * * name

=== RPL_UMODEIS
--- number: 221
--- input
+{
    user_mode_string => '*',
}
--- expected
:127.0.0.1 221 testnick *

=== RPL_SERVLIST
--- number: 234
--- input
+{
    name => 'server.name',
    server => 'server',
    mask => '*',
    type => '',
    hopcount => 5,
    info => 'info',
}
--- expected
:127.0.0.1 234 testnick server.name server *  5 info

=== RPL_SERVLISTEND
--- number: 235
--- input
+{
    mask => '*',
    type => '',
}
--- expected
:127.0.0.1 235 testnick *  :End of service listing

=== RPL_LUSERCLIENT
--- number: 251
--- input
+{
    user_count => 120,
    service_count => 10,
    server_count => 2,
}
--- expected
:127.0.0.1 251 testnick :There are 120 users and 10, services on 2 servers

=== RPL_LUSEROP
--- number: 252
--- input
+{
    operator_count => 10,
}
--- expected
:127.0.0.1 252 testnick 10 :operator(s) online

=== RPL_LUSERUNKNOWN
--- number: 253
--- input
+{
    unknown_count => 5,
}
--- expected
:127.0.0.1 253 testnick 5 :unknown connection(s)

=== RPL_LUSERCHANNELS
--- number: 254
--- input
+{
    channel_count => 50,
}
--- expected
:127.0.0.1 254 testnick 50 :channels formed

=== RPL_LUSERME
--- number: 255
--- input
+{
    client_count => 120,
    server_count => 2,
}
--- expected
:127.0.0.1 255 testnick :I have 120 clients and 2, servers

=== RPL_ADMINME
--- number: 256
--- input
+{
    server => 'server.name',
}
--- expected
:127.0.0.1 256 testnick server.name :Administrative info

=== RPL_ADMINLOC1
--- number: 257
--- input
+{
    admin_info => 'admin info 1',
}
--- expected
:127.0.0.1 257 testnick :admin info 1

=== RPL_ADMINLOC2
--- number: 258
--- input
+{
    admin_info => 'admin info 2',
}
--- expected
:127.0.0.1 258 testnick :admin info 2

=== RPL_ADMINEMAIL
--- number: 259
--- input
+{
    admin_info => 'admin info 3',
}
--- expected
:127.0.0.1 259 testnick :admin info 3

=== RPL_TRYAGAIN
--- number: 263
--- input
+{
    command => 'WHOIS',
}
--- expected
:127.0.0.1 263 testnick WHOIS :Please wait a while and try again.

=== ERR_NOSUCHNICK
--- number: 401
--- input
+{
    nick => 'nick',
}
--- expected
:127.0.0.1 401 testnick nick :No such nick/channel

=== ERR_NOSUCHSERVER
--- number: 402
--- input
+{
    server => 'server.name',
}
--- expected
:127.0.0.1 402 testnick server.name :No such server

=== ERR_NOSUCHCHANNEL
--- number: 403
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 403 testnick #channel :No such channel

=== ERR_CANNOTSENDTOCHAN
--- number: 404
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 404 testnick #channel :Cannot send to channel

=== ERR_TOOMANYCHANNELS
--- number: 405
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 405 testnick #channel :You have joined too many channels

=== ERR_WASNOSUCHNICK
--- number: 406
--- input
+{
    nick => 'nick',
}
--- expected
:127.0.0.1 406 testnick nick :There was no such nickname

=== ERR_TOOMANYTARGETS
--- number: 407
--- input
+{
    target => '*',
    error_code => '255',
    abort_message => 'too many targets.',
}
--- expected
:127.0.0.1 407 testnick * :255 recipients. too many targets.

=== ERR_NOSUCHSERVICE
--- number: 408
--- input
+{
    service => 'service.name',
}
--- expected
:127.0.0.1 408 testnick service.name :No such service

=== ERR_NOORIGIN
--- number: 409
--- input
+{}
--- expected
:127.0.0.1 409 testnick :No origin specified

=== ERR_NORECIPIENT
--- number: 411
--- input
+{
    command => 'PRIVMSG',
}
--- expected
:127.0.0.1 411 testnick :No recipient given (PRIVMSG)

=== ERR_NOTEXTTOSEND
--- number: 412
--- input
+{}
--- expected
:127.0.0.1 412 testnick :No text to send

=== ERR_NOTOPLEVEL
--- number: 413
--- input
+{
    mask => 'mask',
}
--- expected
:127.0.0.1 413 testnick mask :No toplevel domain specified

=== ERR_WILDTOPLEVEL
--- number: 414
--- input
+{
    mask => '~mask@*.*',
}
--- expected
:127.0.0.1 414 testnick ~mask@*.* :Wildcard in toplevel domain

=== ERR_BADMASK
--- number: 415
--- input
+{
    mask => '*AWe+eA+'
}
--- expected
:127.0.0.1 415 testnick *AWe+eA+ :Bad Server/host mask

=== ERR_UNKNOWNCOMMAND
--- number: 421
--- input
+{
    command => 'UNKNOWN',
}
--- expected
:127.0.0.1 421 testnick UNKNOWN :Unknown command

=== ERR_NOMOTD
--- number: 422
--- input
+{}
--- expected
:127.0.0.1 422 testnick :MOTD File is missing

=== ERR_NOADMININFO
--- number: 423
--- input
+{
    server => 'server.name',
}
--- expected
:127.0.0.1 423 testnick server.name :No administrative info available

=== ERR_FILEERROR
--- number: 424
--- input
+{
    file_op => 'open',
    file => 'file',
}
--- expected
:127.0.0.1 424 testnick :File error doing open on file

=== ERR_NONICKNAMEGIVEN
--- number: 431
--- input
+{}
--- expected
:127.0.0.1 431 testnick :No nickname given

=== ERR_ERRONEUSNICKNAME
--- number: 432
--- input
+{
    nick => '+12h',
}
--- expected
:127.0.0.1 432 testnick +12h :Erroneous nickname

=== ERR_NICKNAMEINUSE
--- number: 433
--- input
+{
    nick => 'alreadyuse',
}
--- expected
:127.0.0.1 433 testnick alreadyuse :Nickname is already in use

=== ERR_NICKCOLLISION
--- number: 436
--- input
+{
    nick => 'testnick',
    user => 'user',
    host => 'host.name',
}
--- expected
:127.0.0.1 436 testnick testnick :Nickname collision KILL from user@host.name

=== ERR_UNAVAILRESOURCE
--- number: 437
--- input
+{
    target => '#channel',
}
--- expected
:127.0.0.1 437 testnick #channel :Nick/channel is temporarily unavailable

=== ERR_USERNOTINCHANNEL
--- number: 441
--- input
+{
    nick => 'nick',
    channel => '#channel',
}
--- expected
:127.0.0.1 441 testnick nick #channel :They aren't on that channel

=== ERR_NOTONCHANNEL
--- number: 442
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 442 testnick #channel :You're not on that channel

=== ERR_USERONCHANNEL
--- number: 443
--- input
+{
    nick => 'nick',
    channel => '#channel',
}
--- expected
:127.0.0.1 443 testnick nick #channel :is already on channel

=== ERR_NOLOGIN
--- number: 444
--- input
+{
    nick => 'nick',
}
--- expected
:127.0.0.1 444 testnick nick :User not logged in

=== ERR_SUMMONDISABLED
--- number: 445
--- input
+{}
--- expected
:127.0.0.1 445 testnick :SUMMON has been disabled

=== ERR_USERSDISABLED
--- number: 446
--- input
+{}
--- expected
:127.0.0.1 446 testnick :USERS has been disabled

=== ERR_NOTREGISTERED
--- number: 451
--- input
+{}
--- expected
:127.0.0.1 451 testnick :You have not registered

=== ERR_NEEDMOREPARAMS
--- number: 461
--- input
+{
    command => 'PRIVMSG',
}
--- expected
:127.0.0.1 461 testnick PRIVMSG :Not enough parameters

=== ERR_ALREADYREGISTRED
--- number: 462
--- input
+{}
--- expected
:127.0.0.1 462 testnick :Unauthorized command (already registered)

=== ERR_NOPERMFORHOST
--- number: 463
--- input
+{}
--- expected
:127.0.0.1 463 testnick :Your host isn't among the privileged

=== ERR_PASSWDMISMATCH
--- number: 464
--- input
+{}
--- expected
:127.0.0.1 464 testnick :Password incorrect

=== ERR_YOUREBANNEDCREEP
--- number: 465
--- input
+{}
--- expected
:127.0.0.1 465 testnick :You are banned from this server

=== ERR_YOUWILLBEBANNED
--- number: 466
--- input
+{}
--- expected
:127.0.0.1 466 testnick 

=== ERR_KEYSET
--- number: 467
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 467 testnick #channel :Channel key already set

=== ERR_CHANNELISFULL
--- number: 471
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 471 testnick #channel :Cannot join channel (+l)

=== ERR_UNKNOWNMODE
--- number: 472
--- input
+{
    char => 'q',
    channel => '#channel',
}
--- expected
:127.0.0.1 472 testnick q :is unknown mode char to me for #channel

=== ERR_INVITEONLYCHAN
--- number: 473
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 473 testnick #channel :Cannot join channel (+i)

=== ERR_BANNEDFROMCHAN
--- number: 474
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 474 testnick #channel :Cannot join channel (+b)

=== ERR_BADCHANNELKEY
--- number: 475
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 475 testnick #channel :Cannot join channel (+k)

=== ERR_BADCHANMASK
--- number: 476
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 476 testnick #channel :Bad Channel Mask

=== ERR_NOCHANMODES
--- number: 477
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 477 testnick #channel :Channel doesn't support modes

=== ERR_BANLISTFULL
--- number: 478
--- input
+{
    channel => '#channel',
    char => 'ban',
}
--- expected
:127.0.0.1 478 testnick #channel ban :Channel list is full

=== ERR_NOPRIVILEGES
--- number: 481
--- input
+{}
--- expected
:127.0.0.1 481 testnick :Permission Denied- You're not an IRC operator

=== ERR_CHANOPRIVSNEEDED
--- number: 482
--- input
+{
    channel => '#channel',
}
--- expected
:127.0.0.1 482 testnick #channel :You're not channel operator

=== ERR_CANTKILLSERVER
--- number: 483
--- input
+{}
--- expected
:127.0.0.1 483 testnick :You can't kill a server!

=== ERR_RESTRICTED
--- number: 484
--- input
+{}
--- expected
:127.0.0.1 484 testnick :Your connection is restricted!

=== ERR_UNIQOPPRIVSNEEDED
--- number: 485
--- input
+{}
--- expected
:127.0.0.1 485 testnick :You're not the original channel operator

=== ERR_NOOPERHOST
--- number: 491
--- input
+{}
--- expected
:127.0.0.1 491 testnick :No O-lines for your host

=== ERR_UMODEUNKNOWNFLAG
--- number: 501
--- input
+{}
--- expected
:127.0.0.1 501 testnick :Unknown MODE flag

=== ERR_USERSDONTMATCH
--- number: 502
--- input
+{}
--- expected
:127.0.0.1 502 testnick :Cannot change mode for other users

=== RPL_SERVICEINFO
--- number: 231
--- input
+{}
--- expected

=== RPL_ENDOFSERVICES
--- number: 232
--- input
+{}
--- expected

=== RPL_SERVICE
--- number: 233
--- input
+{}
--- expected

=== RPL_NONE
--- number: 300
--- input
+{}
--- expected

=== RPL_WHOISCHANOP
--- number: 316
--- input
+{}
--- expected

=== RPL_KILLDONE
--- number: 361
--- input
+{}
--- expected

=== RPL_CLOSING
--- number: 362
--- input
+{}
--- expected

=== RPL_CLOSEEND
--- number: 363
--- input
+{}
--- expected

=== RPL_INFOSTART
--- number: 373
--- input
+{}
--- expected

=== RPL_MYPORTIS
--- number: 384
--- input
+{}
--- expected

=== RPL_STATSCLINE
--- number: 213
--- input
+{}
--- expected

=== RPL_STATSNLINE
--- number: 214
--- input
+{}
--- expected

=== RPL_STATSILINE
--- number: 215
--- input
+{}
--- expected

=== RPL_STATSKLINE
--- number: 216
--- input
+{}
--- expected

=== RPL_STATSQLINE
--- number: 217
--- input
+{}
--- expected

=== RPL_STATSYLINE
--- number: 218
--- input
+{}
--- expected

=== RPL_STATSVLINE
--- number: 240
--- input
+{}
--- expected

=== RPL_STATSLLINE
--- number: 241
--- input
+{}
--- expected

=== RPL_STATSHLINE
--- number: 244
--- input
+{}
--- expected

=== RPL_STATSSLINE
--- number: 244
--- input
+{}
--- expected

=== RPL_STATSPING
--- number: 246
--- input
+{}
--- expected

=== RPL_STATSBLINE
--- number: 247
--- input
+{}
--- expected

=== RPL_STATSDLINE
--- number: 250
--- input
+{}
--- expected

=== ERR_NOSERVICEHOST
--- number: 492
--- input
+{}
--- expected
