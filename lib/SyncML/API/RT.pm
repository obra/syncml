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
require SyncML::API::RT::Config;

use base qw/SyncML::Log/;

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

# Loads the RT::Queue that items added on the client get added to.
sub _get_queue {
    my $self = shift;
    my $cu = shift;
    my $q = RT::Queue->new($cu);
    $q->LoadByCols(Name => $SyncML::API::RT::Config::DefaultSyncQueue);
    return $q;
} 

sub get_application_database {
    my $self = shift;
    my $username = shift;

    my $db = {};
    my $cu = $self->_get_rt_current_user($username);
    my $tickets = RT::Tickets->new($cu);
    my $user_id = $cu->Id;
    $tickets->FromSQL(qq{Owner = '$user_id' AND ( Status = 'new' OR Status = 'open')});

    while (my $ticket = $tickets->Next) {
        my $ic = Data::ICal->new;
        $ic->add_property( version => "1.0" );
        my $todo = Data::ICal::Entry::Todo->new;
        $ic->add_entry($todo);
        $todo->add_properties( summary => $ticket->Subject );

        $self->log->info("DB contains ticket: ", $ticket->Subject);

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
    my $self = shift;
    my $dbname = shift; # ignored for now
    my $application_identifier = shift;
    my $username = shift;

    my $cu = $self->_get_rt_current_user($username);

    my $ticket = RT::Ticket->new($cu);
    $ticket->Load($application_identifier);

    unless ($cu->Id) {
        $self->log->warn("Failed to load ticket '$application_identifier'");
        return;
    } 

    my ($ok, $msg) = $ticket->Reject;

    return $ok ? 1 : 0;
}

sub add_item {
    my $self = shift;
    my $dbname = shift; # ignored for now
    my $syncable_item = shift;
    my $username = shift;

    my $cu = $self->_get_rt_current_user($username);
    my $q = $self->_get_queue($cu);

    my $ic = $syncable_item->content_as_object;

    my $ticket = RT::Ticket->new($cu);
    $ticket->Create( Queue => $q->id, 
        Subject => $ic->entries->[0]->property("summary")->[0]->value,
        Owner => $cu->Id);
    # Put in LastUpdated too?

    my $id = $ticket->Id;

    return ($id != 0, $id);
}

1;
