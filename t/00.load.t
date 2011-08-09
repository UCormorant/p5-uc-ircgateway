use Test::More tests => 3;

BEGIN {
use_ok( 'Uc::IrcGateway' );
use_ok( 'Uc::IrcGateway::Twitter' );
use_ok( 'Uc::IrcGateway::Util::User' );
use_ok( 'Uc::IrcGateway::Util::TypableMap' );
}

diag( "Testing Uc::IrcGateway $Uc::IrcGateway::VERSION" );
