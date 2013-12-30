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

use JSON ();
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
    nickname => qr{^[\w][-\w$SPECIAL]*$}, # ï∂éöêîêßå¿,êÊì™ÇÃêîéöã÷é~ÇÕàµÇ¢Ç√ÇÁÇ¢ÇÃÇ≈ÇµÇ‹ÇπÇÒ
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
    to_json
    from_json
    eq_hash

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
    $color //= '';

    $color ne '' ? "\03$color$text\03" : $text;
}

sub replace_crlf { $_[0] =~ s/[\r\n]+/ /gr; }

my $JSON;
sub to_json {
    $JSON //= JSON->new->pretty->allow_nonref->allow_blessed;
    my $value = shift;
    my %opts = @_ == 1 ? %{$_[0]} : @_;

    my $prv = $JSON;
    if (%opts) {
        $prv = JSON->new->pretty->allow_nonref->allow_blessed;
        for my $attr (qw(
            ascii latin1 utf8
            pretty indent space_before space_after
            relaxed canonical
            allow_nonref allow_unknown allow_blessed convert_blessed
            shrink max_depth max_size
        )) {
            $prv->$attr(delete $opts{$attr}) if exists $opts{$attr};
        }
    }
    $prv->encode($value) =~ s/$REGEX{chomp}//r;
}
sub from_json {
    $JSON //= JSON->new->pretty->allow_nonref->allow_blessed;
    $JSON->decode(+shift);
}

sub eq_hash {
    my ($hash1, $hash2) = @_;
    (join($NUL, sort grep { defined } %$hash1) eq join($NUL, sort grep { defined } %$hash2));
}


1; # Magic true value required at end of module
__END__

=encoding utf-8

=head1 NAME

Uc::IrcGateway::Common - Utilities for Uc::IrcGateway


=head1 SYNOPSIS

  use Uc::IrcGateway::Common;
      # will import following variables and functions

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
  to_json
  from_json
  eq_hash

  mk_msg parse_irc_msg split_prefix decode_ctcp encode_ctcp
  prefix_nick prefix_user prefix_host is_nick_prefix join_prefix

=head1 DESCRIPTION

common variables and utilities for Uc::IrcGateway.

=head1 INTERFACE

=head2 Functions

=over 2

=item is_valid_channel_name($channel_name)

return ture if $channel_name is valid as IRC channel name.

it uses $Uc::IrcGateway::Common::REGEX{channel} to check.

=item %option = opt_parser($option_string)

parse $option_string to hash object.

example:

  %option = opt_parser('foo bar=bar_text baz=2 baz=3');

  # ( foo => 1, bar => 'bar_text', baz => 3 )

=item $decorated = decorate_text($text, $color)

it changes color of $text to $color.

The color indexes 0 to 15 represent the following colors in mIRC:

=over 4

=item 0.

white

=item 1.

black

=item 2.

blue (navy)

=item 3.

green

=item 4.

red

=item 5.

brown (maroon)

=item 6.

purple

=item 7.

orange (olive)

=item 8.

yellow

=item 9.

light green (lime)

=item 10.

teal (a green/blue cyan)

=item 11.

light cyan (cyan) (aqua)

=item 12.

light blue (royal)

=item 13.

pink (light purple) (fuchsia)

=item 14.

grey

=item 15.

light grey (silver)

=back

see also mIRC colors (L<http://www.mirc.com/colors.html>).

=item $nolinebreak_text = replace_crlf($text_includes_linebreak)

replace crlf to space in $text_includes_linebreak;

it uses $Uc::IrcGateway::Common::REGEX{crlf} to replace.

=item $json = to_json($object, $JSON_options)

encode $object to JSON string by using L<JSON>.

defalt JSON instance are created by following:

  JSON->new->pretty->allow_nonref->allow_blessed

$JSON_options allows following settings:

  ascii latin1 utf8
  pretty indent space_before space_after
  relaxed canonical
  allow_nonref allow_unknown allow_blessed convert_blessed
  shrink max_depth max_size

see also L<JSON#COMMON_OBJECT-ORIENTED_INTERFACE>

=item $object = from_json($json)

decode $json string to perl variable.

using JSON instance is same as to_json.

=item eq_hash($hash1, $hash2)

compare twe hashes whether they are same or not.
return true if the key and value of two hashes are completely the same.

note: it can't compare nested hashes.

=item Anyevent::IRC::Util funtions

the following functions are imported by L<AnyEvent::IRC::Util>:

  mk_msg parse_irc_msg split_prefix decode_ctcp encode_ctcp
  prefix_nick prefix_user prefix_host is_nick_prefix join_prefix

=back

=head2 Variables

=over 2

=item $MAXBYTE = 512

maxbyte of an IRC message.

=item $NUL = "\0"

null.

=item $BELL = "\07"

bell.

=item $CRLF = "\015\012"

line break of IRC message.

=item $SPECIAL = '\[\]\\\`\_\^\{\|\}'

special character for IRC channel name and user nickname.

=item $SPCRLFCL = " $CRLF:"

space, crlf and colon.

=item %REGEX

shared pattern in Uc::IrcGateway.

  crlf     => qr{\015*\012},
  chomp    => qr{[$CRLF$NUL]+$},
  channel  => qr{^(?:[#+&]|![A-Z0-9]{5})[^$SPCRLFCL,$BELL]+(?:\:[^$SPCRLFCL,$BELL]+)?$},
  nickname => qr{^[\w][-\w$SPECIAL]*$}, # ï∂éöêîêßå¿,êÊì™ÇÃêîéöã÷é~ÇÕàµÇ¢Ç√ÇÁÇ¢ÇÃÇ≈ÇµÇ‹ÇπÇÒ

=back


=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
L<https://github.com/UCormorant/p5-uc-ircgateway/issues>


=head1 AUTHOR

U=Cormorant E<lt>u@chimata.orgE<gt>


=head1 SEE ALSO

=over

=item Uc::IrcGateway L<https://github.com/UCormorant/p5-uc-ircgateway>

=back


=head1 LICENCE AND COPYRIGHT

Copyright (C) 2011-2013, U=Cormorant. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut
