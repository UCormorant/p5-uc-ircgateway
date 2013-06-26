package EchoServer;
our $VERSION = Uc::IrcGateway->VERSION;

use 5.014;
use common::sense;
use warnings qw(utf8);

use parent 'Uc::IrcGateway';
__PACKAGE__->load_plugins(qw/DefaultSet/);

1;
