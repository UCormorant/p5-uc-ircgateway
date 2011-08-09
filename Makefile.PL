use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Uc::IrcGateway',
    AUTHOR              => 'U=Cormorant <u@chimata.org>',
    VERSION_FROM        => 'lib/Uc/IrcGateway.pm',
    ABSTRACT_FROM       => 'lib/Uc/IrcGateway.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'version'    => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Uc-IrcGateway-*' },
);
