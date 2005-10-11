use strict;
use warnings;

package SyncML::API::YAML;
use String::Koremutake;

# This is pretty damn prototypy
# Anything in this file that doesn't begin with an underscore is called from the
# Engine, and thus is at least theoretically part of the "API"
#
# Note that communication between the Engine and the ApplicationInterface should
# use SyncableItems, not SyncDBEntrys -- the ApplicationInterface should be
# unaware of client_identifiers
use YAML         ();

my $APPLICATION_DATABASE = "eg/database";
my $APPLICATION_AUTH_DATABASE = "eg/app_auth_db";

sub new { bless {}, shift } 

sub authenticated {
    my $self = shift;
    my $user_password = shift;
    
    return unless defined $user_password;

    my ($user, $password) = $user_password =~ /\A ([^:]*) : (.*) \z/xms;

    return unless defined $user;

    my $authdb = YAML::LoadFile($APPLICATION_AUTH_DATABASE);

    return unless $authdb;
    return unless $authdb->{$user};
    return unless $authdb->{$user}{'password'} eq $password;

    return $user;
}

sub get_application_database {
    my $self = shift;
    my $db   = YAML::LoadFile($APPLICATION_DATABASE);

    for my $app_id ( keys %$db ) {
        my $ic = Data::ICal->new;
        $ic->add_property( version => "1.0" );
        my $todo = Data::ICal::Entry::Todo->new;
        $ic->add_entry($todo);
        $todo->add_properties( summary => $db->{$app_id}{summary}, );

        my $syncitem = SyncML::SyncableItem->new;
        $syncitem->application_identifier($app_id);
        $syncitem->content( $ic->as_string );
        $syncitem->type("text/x-vcalendar");
        $syncitem->last_modified_as_seconds( $db->{$app_id}{last_modified} );

        $db->{$app_id} = $syncitem;
    }

    return $db;
}

sub _save_application_database {
    my $self = shift;
    my $db   = shift;

    my $outdb = {};

    for my $app_id ( keys %$db ) {
        my $syncitem = $db->{$app_id};
        my $ic       = $syncitem->content_as_object;

        $outdb->{$app_id} = {
            summary => $ic->entries->[0]->property("summary")->[0]->value,
            last_modified => $syncitem->last_modified_as_seconds,
        };
    }
    YAML::DumpFile( $APPLICATION_DATABASE, $outdb );
}

# Note that this also gets called if the application deleted something but the
# client modified it (and the client's mods thus win) -- so this can be called
# on a deleted item!
sub update_item {
    my $self = shift;
    my $dbname = shift; # ignored for now
    my $syncable_item = shift;

    my $db = $self->get_application_database();
    $db->{ $syncable_item->application_identifier } = $syncable_item;
    $self->_save_application_database($db);
    return 1;
} 

sub delete_item {
    my $self = shift;
    my $dbname = shift; # ignored for now
    my $application_identifier = shift;

    my $db = $self->get_application_database();
    delete $db->{ $application_identifier };
    $self->_save_application_database($db);
    return 1;
}

sub add_item {
    my $self = shift;
    my $dbname = shift; # ignored for now
    my $syncable_item = shift;

    my $db = $self->get_application_database();

    my $k = String::Koremutake->new;
    my $app_id;
    FIND_APP_ID:
    while (1) {
        $app_id = $k->integer_to_koremutake(int rand(2_000_000));
        last FIND_APP_ID if !defined $db->{$app_id};
    } 

    $syncable_item->application_identifier($app_id);
    $db->{$app_id} = $syncable_item;
    $self->_save_application_database($db);
    return (1, $app_id);
}

1;
