# NAME

Uc::IrcGateway - プラガブルなオレオレIRCゲートウェイ基底クラス



# VERSION

This document describes Uc::IrcGateway version v3.1.6



# SYNOPSIS

    package MyIrcGateway;
    use parent qw(Uc::IrcGateway);
    __PACKAGE__->load_components(qw/AutoRegisterUser/);
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



# CONFIGURATION AND ENVIRONMENT



# DEPENDENCIES



# BUGS AND LIMITATIONS

Please report any bugs or feature requests to
[https://github.com/UCormorant/p5-uc-ircgateway/issues](https://github.com/UCormorant/p5-uc-ircgateway/issues)



# AUTHOR

U=Cormorant <u@chimata.org>



# LICENCE AND COPYRIGHT

Copyright (C) 2011-2013, U=Cormorant. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See [perlartistic](http://search.cpan.org/perldoc?perlartistic).
