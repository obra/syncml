use Test::More tests => 2;

BEGIN {
use_ok( 'SyncML::Message' );
use_ok( 'SyncML::Message::Command' );
}

diag( "Testing SyncML::Message $SyncML::Message::VERSION" );
