use inc::Module::Install;

name ('SyncML');
author ('David Glasser <glasser@bestpractical.com>');
version_from ('lib/SyncML/Message.pm');
abstract_from('lib/SyncML/Message.pm');
license('perl');
requires('Test::More');

&WriteAll;
