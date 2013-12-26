use utf8;
use strict;
use Test::More tests => 2;
use Test::TCP;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
use Uc::IrcGateway::Common;

use IO::Socket::INET ();
use Sys::Hostname qw(hostname);
use AnyEvent::IRC::Client ();
use AE ();
use Path::Class qw(dir file);

my $app_dir = tempdir(CLEANUP => 1);

subtest 'new' => sub {
    my ($ircd, %args);
    %args = (
        host => '0.0.0.0',
        port => empty_port(),
        time_zone => 'Asia/Tokyo',
        servername => 'UcIrcServer',
        gatewayname => '*bot',
        app_dir => $app_dir,
        motd_file => 'motd.txt',
        motd_text => 'hogefuga',

        ping_timeout => 10,
        charset => 'euc-jp',
        err_charset => 'cp932',

        test_option1 => 'foo',
        test_option2 => ['bar'],
        test_option3 => { baz => 'baz' },
    );

    $ircd = Uc::IrcGateway->new( app_dir => $app_dir );
    ok($ircd, '#new without arguments');

    can_ok($ircd, qw(
        host port time_zone
        servername gatewayname
        motd_file motd_text
        ping_timeout to_prefix
        charset err_charset
        codec err_codec
        handles
        ctime
    ));

    ok(defined $ircd->host, 'check host');
    ok(defined $ircd->port, 'check port');
    ok(defined $ircd->time_zone, 'check time_zone');
    is($ircd->servername, scalar hostname(), 'check servername');
    like($ircd->gatewayname, qr/^\S+$/, 'check gatewayname');
    isa_ok($ircd->app_dir, 'Path::Class::Dir', 'check app_dir');
    isa_ok($ircd->motd_file, 'Path::Class::File', 'check motd_file');
    is($ircd->motd_text, undef, 'check motd_text');
    ok(defined $ircd->ping_timeout, 'check ping_timeout');
    is($ircd->to_prefix, $ircd->host, 'check to_prefix');
    ok(defined $ircd->charset, 'check charset');
    ok(defined $ircd->err_charset, 'check err_charset');
    like(ref $ircd->codec, qr/^Encode::/, 'check codec');
    like(ref $ircd->err_codec, qr/^Encode::/, 'check err_codec');

    for $ircd (Uc::IrcGateway->new(%args), Uc::IrcGateway->new(\%args)) {
        ok($ircd, '#new with arguments');
        is($ircd->host, $args{host}, 'check host');
        is($ircd->port, $args{port}, 'check port');
        is($ircd->time_zone, $args{time_zone}, 'check time_zone');
        is($ircd->servername, $args{servername}, 'check servername');
        is($ircd->gatewayname, $args{gatewayname}, 'check gatewayname');
        is($ircd->app_dir->stringify, dir($args{app_dir})->stringify, 'check app_dir');
        is($ircd->motd_file->stringify, file($args{app_dir}, $args{motd_file})->stringify, 'check motd_file');
        is($ircd->motd_text, 'hogefuga', 'check motd_text');
        is($ircd->ping_timeout, $args{ping_timeout}, 'check ping_timeout');
        is($ircd->to_prefix, $ircd->host, 'check to_prefix');
        is($ircd->charset, $args{charset}, 'check charset');
        is($ircd->err_charset, $args{err_charset}, 'check err_charset');
        is($ircd->codec->name, $args{charset}, 'check codec');
        is($ircd->err_codec->name, $args{err_charset}, 'check err_codec');

        is_deeply(
            [@{$ircd}{qw/test_option1 test_option2 test_option3/}],
            [@args{qw/test_option1 test_option2 test_option3/}],
            'check extra arguments',
        );
    }
};

subtest 'run' => sub {
    test_tcp(
        server => setup_ircd('Uc::IrcGateway'),
        client => sub {
            my $port = shift;
            my $conn = IO::Socket::INET->new(PeerAddr => "127.0.0.1:$port", Timeout => 1);

            ok($conn, "check connection");
        },
    );
};

done_testing;
