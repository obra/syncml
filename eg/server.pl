use strict;
use warnings;

use SyncML::SimpleServer;
use SyncML::API::YAML;
use SyncML::Log;

SyncML::Log->log_init('eg/simple-server.logconf');

my $api = SyncML::API::YAML->new;
my $server = SyncML::SimpleServer->new;
$server->api($api);


$server->run;

