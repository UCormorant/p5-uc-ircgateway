# vim: set ft=perl :
use utf8;
use strict;
use Test::More tests => 2;
use Test::Difflet qw(is_deeply);

use t::Util;
use Uc::IrcGateway;
Uc::IrcGateway->load_plugins(qw/DefaultSet CustomRegisterUser/);

no strict 'refs';

eval { new_ircd('Uc::IrcGateway'); };
ok $@, 'dies when register_user method is not defined';

*{'Uc::IrcGatway::register_user'} = sub {};
eval { new_ircd('Uc::IrcGateway'); };
ok !$@, 'lives when register_user method is defined';

done_testing;
