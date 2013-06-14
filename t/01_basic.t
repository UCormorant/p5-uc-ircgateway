use strict;
use Test::More tests => 3;
use Test::TCP;
use Test::Difflet;

use lib qw(lib ../lib);
use Uc::IrcGateway;
use IO::Socket::INET ();
use Sys::Hostname qw(hostname);
use Path::Class qw(file);
use AnyEvent::IRC::Client ();
use AE ();
use Data::Dumper qw(Dumper);

my $CRLF = $Uc::IrcGateway::CRLF;
my $server_code = sub {
    my $port = shift;
    my $cv = AE::cv;

    my $ircd = Uc::IrcGateway->new(port => $port, debug => 1);
    $ircd->run;

    $cv->recv;
};

subtest '#new' => sub {
    my ($ircd, %args);
    %args = (
        host => '0.0.0.0',
        port => empty_port(),
        time_zone => 'Asia/Tokyo',
        servername => 'UcIrcServer',
        gatewayname => '*bot',
        motd => file('motd.txt'),
        ping_timeout => 10,
        charset => 'euc-jp',
        err_charset => 'cp932',

        test_option1 => 'foo',
        test_option2 => ['bar'],
        test_option3 => { baz => 'baz' },
    );

    $ircd = Uc::IrcGateway->new();
    ok($ircd, '#new without arguments');

    can_ok($ircd, qw(
        host port time_zone
        servername gatewayname motd
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
    isa_ok($ircd->motd, 'Path::Class::File', 'check motd');
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
        is($ircd->motd->stringify, $args{motd}->stringify, 'check motd');
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

subtest '#run' => sub {
    test_tcp(
        server => $server_code,
        client => sub {
            my $port = shift;
            my $conn = IO::Socket::INET->new("127.0.0.1:$port");

            $conn->print("PING$CRLF");
            ok($conn->getline, "check communication");
        },
    );
};

subtest 'register client' => sub {
    test_tcp(
        server => $server_code,
        client => sub {
            my $port = shift;
            my $cv = AE::cv;
            my $conn = AnyEvent::IRC::Client->new();

            $conn->reg_cb(
                irc_001 => sub {
                    ok 1, 'irc_001 WELCOME';
                },
                registered => sub {
                    ok 1, 'registered';
                    $cv->send();
                },
                error => sub {
                    my ($conn, $code, $message, $ircmsg) = @_;
                    pass("$code: $message, ". Dumper($ircmsg));
                    $cv->send();
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
};

done_testing();
