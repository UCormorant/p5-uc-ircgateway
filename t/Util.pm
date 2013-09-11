package t::Util;
use strict;
use warnings;
use utf8;
use lib './t/lib';
use Test::More;
use Test::TCP qw(empty_port);
use AE;
use File::Temp qw(tempdir);
use Path::Class qw(file);

use parent 'Exporter';
our @EXPORT = qw(
    tempdir file
    new_ircd
    setup_ircd
);

sub import {
    strict->import;
    warnings->import;
    utf8->import;
    __PACKAGE__->export_to_level(1, @_)
}

sub new_ircd {
    my $class  = shift;
    my %option = scalar @_ ? %{+shift} : ();
    $option{port} //= empty_port();
    $option{app_dir} //= tempdir(CLEANUP => 1);

    $class->new(%option);
}

sub setup_ircd {
    my $class  = shift;
    my %option = scalar @_ ? %{+shift} : ();

    sub {
        my $port = shift;
        my $cv = AE::cv;
        new_ircd($class, { port => $port, condvar => $cv, %option })->run;
        $cv->recv;
    };
}

1;
