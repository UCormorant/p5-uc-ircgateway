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
        select my $LOCALOUT;
        # use inc::Module::Install 0.69; # for configure_requires
        eval qq{use inc::Module::Install 0.69; 1;} or push @not_available, 'inc::Module::Install';
        select STDOUT;
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

name 'Uc-IrcGateway';
reference_module 'lib/Uc/IrcGateway.pm';
auto_set_repository;

test_requires 'Test::More' => '0.94'; # for subtest
test_requires 'Test::TCP';
test_requires 'Test::Difflet';

requires 'Mouse' => '1.04';
requires 'Any::Moose' => '0.11'; # for ::Util::TypeConstraints
requires 'AnyEvent' => '7.04';
requires 'AnyEvent::IRC' => '0.6'; # for is_nick_prefix, join_prefix
requires 'Path::Class' => '0.29';
requires 'UNIVERSAL::which' => '0.06';

# utig.pl
requires 'Uc::Model::Twitter' => '1.00';
requires 'Net::Twitter::Lite';
requires 'AnyEvent::Twitter';
requires 'AnyEvent::Twitter::Stream';
requires 'HTML::Entities';
requires 'DateTime::Format::DateParse';
requires 'Config::Pit';
requires 'Clone';
requires 'YAML';

tests_recursive;
recursive_author_tests 'xt';

WriteAll;
