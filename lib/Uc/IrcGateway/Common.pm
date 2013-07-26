package Uc::IrcGateway::Common;
use 5.014;
use warnings;
use utf8;
use parent 'Exporter';

use Scalar::Util qw(blessed);

use Uc::IrcGateway::Connection;
use Uc::IrcGateway::Logger;
use Uc::IrcGateway::Message;
use Uc::IrcGateway::TempUser;
use Uc::IrcGateway::User;

use AnyEvent::IRC::Util qw(
    mk_msg parse_irc_msg split_prefix decode_ctcp encode_ctcp
    prefix_nick prefix_user prefix_host is_nick_prefix join_prefix
);

our $MAXBYTE  = 512;
our $NUL      = "\0";
our $BELL     = "\07";
our $CRLF     = "\015\012";
our $SPECIAL  = '\[\]\\\`\_\^\{\|\}';
our $SPCRLFCL = " $CRLF:";
our %REGEX = (
    crlf     => qr{\015*\012},
    chomp    => qr{[$CRLF$NUL]+$},
    channel  => qr{^(?:[#+&]|![A-Z0-9]{5})[^$SPCRLFCL,$BELL]+(?:\:[^$SPCRLFCL,$BELL]+)?$},
    nickname => qr{^[\w][-\w$SPECIAL]*$}, # •¶Žš”§ŒÀ,æ“ª‚Ì”Žš‹ÖŽ~‚Íˆµ‚¢‚Ã‚ç‚¢‚Ì‚Å‚µ‚Ü‚¹‚ñ
);

BEGIN {
    no strict 'refs';
    while (my ($code, $name) = each %AnyEvent::IRC::Util::RFC_NUMCODE_MAP) {
        *{$name} = sub () { $code };
    }
}

our @EXPORT = qw(
    $MAXBYTE
    $NUL
    $BELL
    $CRLF
    $SPECIAL
    $SPCRLFCL
    %REGEX

    is_valid_channel_name
    opt_parser
    decorate_text
    replace_crlf

    mk_msg parse_irc_msg split_prefix decode_ctcp encode_ctcp
    prefix_nick prefix_user prefix_host is_nick_prefix join_prefix
);
push @EXPORT, values %AnyEvent::IRC::Util::RFC_NUMCODE_MAP;

sub import {
    utf8->import;
    warnings->import;
    __PACKAGE__->export_to_level(1, @_);
}

sub is_valid_channel_name { $_[0] =~ /$REGEX{channel}/; }

sub opt_parser { my %opt; $opt{$1} = $2 ? $2 : 1 while $_[0] =~ /(\w+)(?:=(\S+))?/g; %opt }

sub decorate_text {
    my ($text, $color) = @_;

    $color ne '' ? "\03$color$text\03" : $text;
}

sub replace_crlf { $_[0] =~ s/[\r\n]+/ /gr; }

1;
