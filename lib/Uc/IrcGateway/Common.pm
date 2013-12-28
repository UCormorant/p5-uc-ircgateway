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
        for my $attr (qw(
            ascii latin1 utf8
            pretty indent space_before space_after
            relaxed canonical
            allow_nonref allow_unknown allow_blessed convert_blessed
            shrink max_depth max_size
        )) {
            $prv = $prv->$attr(delete $opts{$attr}) if exists $opts{$attr};
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

=encoding utf8

=head1 NAME

Uc::IrcGateway::Common - Utilities for Uc::IrcGateway


=head1 SYNOPSIS

    use Uc::IrcGateway::Common;


=head1 DESCRIPTION


=head1 INTERFACE


=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
L<https://github.com/UCormorant/p5-uc-ircgateway/issues>


=head1 SEE ALSO

=over

=item L<Uc::IrcGateway>

=back


=head1 AUTHOR

U=Cormorant  C<< <u@chimata.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011-2013, U=Cormorant C<< <u@chimata.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
