use utf8;
use strict;
use Test::More tests => 6;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway::Common;

subtest 'import elements' => sub {
    our ($MAXBYTE, $NUL, $BELL, $CRLF, $SPECIAL, $SPCRLFCL, %REGEX);
    ok($MAXBYTE, '$MAXBYTE');
    ok($NUL,     '$NUL');
    ok($BELL,    '$BELL');
    ok($CRLF,    '$CRLF');
    ok($SPECIAL, '$SPECIAL');
    ok(%REGEX,   '%REGEX');

    can_ok(__PACKAGE__, qw(
        is_valid_channel_name
        opt_parser
        decorate_text
        replace_crlf
        to_json

        mk_msg parse_irc_msg split_prefix decode_ctcp encode_ctcp
        prefix_nick prefix_user prefix_host is_nick_prefix join_prefix
    ));
};

subtest 'is_valid_channel_name' => sub {
    ok(    is_valid_channel_name('#channel'), 'valid #channel');
    ok(    is_valid_channel_name('+channel'), 'valid +channel');
    ok(    is_valid_channel_name('&channel'), 'valid &channel');
    ok(    is_valid_channel_name('!QR7Y8channel'), 'valid !QR7Y8channel');
    ok(    is_valid_channel_name('#cha:nnel'), 'valid #cha:nnel');
    ok(not(is_valid_channel_name('channel')), 'invalid channel');
    ok(not(is_valid_channel_name('&:channel')), 'invalid &:channel');
    ok(not(is_valid_channel_name('+ch annel')), 'invalid +ch annel');
    ok(not(is_valid_channel_name("#ch\nannel")), 'invalid #ch\nannel');
};

subtest 'opt_parser' => sub {
    is_deeply({opt_parser('foo bar=baz')}, { foo => 1, bar => 'baz' }, "parse 'foo bar=baz'");
    is_deeply({opt_parser('one one=two,three four')}, { one => 'two,three', four => 1 }, "parse 'one one=two,three four'");
};

subtest 'decorate_text' => sub {
    is(decorate_text('decorate text', 14), "\03"."14decorate text"."\03", 'color 14');
    is(decorate_text('decorate text'), "decorate text", 'unset color');
};

subtest 'replace_crlf' => sub {
    is(replace_crlf(<<'_TEXT_'), 'a b b c c d d e e f ', '\n to SPACE');
a b
b c

c d

d e
e f
_TEXT_
};

subtest 'to_json' => sub {
    like(to_json({ one => 'two', three => 'four' }), qr!{
\s+(?:"one" : "two",
\s+"three" : "four"|"three" : "four",
\s+"one" : "two")
}!, 'to_json');
};


done_testing;
