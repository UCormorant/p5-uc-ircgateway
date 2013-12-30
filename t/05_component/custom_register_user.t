# vim: set ft=perl :
use utf8;
use strict;
use Test::More tests => 2;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;

no strict 'refs';

eval { Uc::IrcGateway->load_components(qw/CustomRegisterUser/); };
ok $@, 'dies when register_user method is not defined';

*{'Uc::IrcGateway::register_user'} = sub {};
eval { Uc::IrcGateway->load_components(qw/CustomRegisterUser/); };
ok !$@, 'lives when register_user method is defined'; diag $@;

done_testing;
