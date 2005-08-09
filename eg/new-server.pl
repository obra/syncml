use strict;
use warnings;

use FindBin;

use SyncML::SimpleServer;
my $server = SyncML::SimpleServer->new;

$server->yaml_database("$FindBin::Bin/database");
$server->run;

