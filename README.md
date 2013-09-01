# NAME

Uc::IrcGateway - プラガブルなオレオレIRCゲートウェイ基底クラス



# VERSION

This document describes Uc::IrcGateway version 3.0.0



# SYNOPSIS

    package MyIrcGateway;
    use parent qw(Uc::IrcGateway);
    __PACKAGE__->load_plugins(qw/DefaultSet/);

    package main;

    my $ircd = MyIrcGateway->new(
        host => '0.0.0.0',
        port => 6667,
        time_zone => 'Asia/Tokyo',
        debug => 1,
    );

    $ircd->run();
    AE::cv->recv();



# DESCRIPTION



# INTERFACE



# DIAGNOSTICS

- `Error message here, perhaps with %s placeholders`

    \[Description of error here\]

- `Another error message here`

    \[Description of error here\]

    \[Et cetera, et cetera\]



# CONFIGURATION AND ENVIRONMENT

Uc::IrcGateway requires no configuration files or environment variables.



# DEPENDENCIES

None.



# INCOMPATIBILITIES

None reported.



# BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
[https://github.com/UCormorant/p5-uc-ircgateway/issues](https://github.com/UCormorant/p5-uc-ircgateway/issues)



# AUTHOR

U=Cormorant  `<u@chimata.org>`



# LICENCE AND COPYRIGHT

Copyright (c) 2011-2013, U=Cormorant `<u@chimata.org>`. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See [perlartistic](http://search.cpan.org/perldoc?perlartistic).



# DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
