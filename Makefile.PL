use strict;
use warnings;

# plagiarized by http://unknownplace.org/memo/2012/08/31/1/
BEGIN {
    my @devmods = qw(
        Module::Install::AuthorTests
        Module::Install::ReadmeMarkdownFromPod
        Module::Install::Repository
    );
    my @not_available;

    {
        local *STDOUT;
        eval qq{use inc::Module::Install; 1;} or push @not_available, 'inc::Module::Install';
    }

    for my $mod (@devmods) {
        eval qq{require $mod} or push @not_available, $mod;
    }
    if (@not_available) {
        print qq{# The following modules are not available.\n};
        print qq{# `$^X $0 | cpanm` will install them:\n};
        print $_, "\n" for @not_available;
        print "\n";
        exit -1;
    }
}

use inc::Module::Install 0.69; # for configure_requires

name 'Uc-IrcGateway';
reference_module 'lib/Uc/IrcGateway.pm';
auto_set_repository;

test_requires 'Test::More' => '0.94'; # for subtest

requires 'common::sense' => 0; # I want to set '3.6', but common::sense does not have $VERSION !

tests_recursive;
recursive_author_tests 'xt';

WriteAll;
