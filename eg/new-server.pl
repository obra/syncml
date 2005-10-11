use strict;
use warnings;

use SyncML::SimpleServer;
use SyncML::API::YAML;

my $api = SyncML::API::YAML->new;
my $server = SyncML::SimpleServer->new;
$server->api($api);

$server->run;

