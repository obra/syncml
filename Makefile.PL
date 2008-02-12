use inc::Module::Install;

name ('SyncML');
author ('David Glasser <glasser@bestpractical.com>');
version_from ('lib/SyncML/Message.pm');
abstract_from('lib/SyncML/Message.pm');
license('perl');
requires('Test::More' => 0,
         'XML::Twig' => 0,
        'Test::Class' => 0,
        'Sys::HostIP' => 0,
        'Sub::Installer' => 0,
        'XML::WBXML' => 0
        );

&WriteAll;
