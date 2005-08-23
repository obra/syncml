use strict;
use warnings;

package SyncML::ApplicationInterface;

# This is pretty damn prototypy
use YAML         ();

my $APPLICATION_DATABASE = "eg/database";
my $APPLICATION_AUTH_DATABASE = "eg/app_auth_db";


sub authenticated {
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

sub save_application_database {
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


1;
