use strict;
use warnings;

package SyncML::API::RT;

# This is pretty damn prototypy
# Anything in this file that doesn't begin with an underscore is called from the
# Engine, and thus is at least theoretically part of the "API"
#
# Note that communication between the Engine and the ApplicationInterface should
# use SyncableItems, not SyncDBEntrys -- the ApplicationInterface should be
# unaware of client_identifiers

use lib '/Users/glasser/BestPractical/rt-3.5/lib';
use RT;
RT::LoadConfig();
RT::Init();

sub new { bless {}, shift } 

sub authenticated {
    my $self = shift;
    my $user_password = shift;
    
    return unless defined $user_password;

    my ($user, $password) = $user_password =~ /\A ([^:]*) : (.*) \z/xms;

    return unless defined $user;

    my $cu = $self->_get_rt_current_user($user);
    return unless $cu and $cu->IsPassword($password);

    return $user;
}

sub _get_rt_current_user {
    my $self = shift;
    my $username = shift;
    my $cu = RT::CurrentUser->new;
    $cu->LoadByName($username);
    return unless $cu->Id;
    return $cu;
} 

sub get_application_database {
    my $self = shift;
    my $username = shift;

    my $db = {};

    my $cu = $self->_get_rt_current_user($username);
    my $tickets = RT::Tickets->new($cu);
    $tickets->LimitOwner(VALUE => $cu->id);

    while (my $ticket = $tickets->Next) {
        my $ic = Data::ICal->new;
        $ic->add_property( version => "1.0" );
        my $todo = Data::ICal::Entry::Todo->new;
        $ic->add_entry($todo);
        $todo->add_properties( summary => $ticket->Subject );

        my $syncitem = SyncML::SyncableItem->new;
        $syncitem->application_identifier($ticket->Id);
        $syncitem->content( $ic->as_string );
        $syncitem->type("text/x-vcalendar");

        $syncitem->last_modified_as_seconds( $ticket->LastUpdatedObj->Unix );

        $db->{$ticket->Id} = $syncitem;
    }

    return $db;
}


# Note that this also gets called if the application deleted something but the
# client modified it (and the client's mods thus win) -- so this can be called
# on a deleted item!
sub update_item {
return 1;
    my $self = shift;
    my $dbname = shift; # ignored for now
    my $syncable_item = shift;

    my $db = $self->get_application_database();
    $db->{ $syncable_item->application_identifier } = $syncable_item;
    $self->_save_application_database($db);
    return 1;
} 

sub delete_item {
return 1;
    my $self = shift;
    my $dbname = shift; # ignored for now
    my $application_identifier = shift;

    my $db = $self->get_application_database();
    delete $db->{ $application_identifier };
    $self->_save_application_database($db);
    return 1;
}

sub add_item {
return (1, 200);
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
