use strict;
use warnings;

use SyncML::SimpleServer;
use SyncML::API::RT;
use SyncML::Log;

SyncML::Log->log_init('eg/simple-server.logconf');

my $api = SyncML::API::RT->new;
my $server = SyncML::SimpleServer->new;
$server->api($api);


$server->run;

