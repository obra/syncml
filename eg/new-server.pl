use strict;
use warnings;

use SyncML::SimpleServer;
my $server = SyncML::SimpleServer->new;

$server->run;

