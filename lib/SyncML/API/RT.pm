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

require SyncML::API::RT::Config;

use DateTime;
use SyncML::APIReturn;

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
        my $syncitem = $self->_syncable_for_ticket($ticket);
        
        $db->{$ticket->Id} = $syncitem;
    }

    return $db;
}

sub _syncable_for_ticket {
    my $self = shift;
    my $ticket = shift;
    
    my $now = DateTime->now;

    my $ic = Data::ICal->new;
    $ic->add_property( version => "1.0" );
    my $todo = Data::ICal::Entry::Todo->new;
    $ic->add_entry($todo);
    $todo->add_properties( summary => $ticket->Subject );
    $todo->add_properties( description => 
        qq{Nice report: Last thought about at @{[ $now->hms ]} From queue: @{[ $ticket->QueueObj->Name ]}; Status: @{[ $ticket->Status ]}});

    my $syncitem = SyncML::SyncableItem->new;
    $syncitem->application_identifier($ticket->Id);
    $syncitem->content( $ic->as_string );
    $syncitem->type("text/x-vcalendar");

    $syncitem->last_modified_as_seconds( $ticket->LastUpdatedObj->Unix );

    return $syncitem;
} 


# Note that this also gets called if the application deleted something but the
# client modified it (and the client's mods thus win) -- so this can be called
# on a deleted item!
sub update_item {
    my $self = shift;
    my $dbname = shift; # ignored for now
    my $syncable_item = shift;
    my $username = shift;

    my $just_checking = shift;

    my $ic = $syncable_item->content_as_object;
    my $status = $ic->entries->[0]->property("status")->[0]->value;

    my $ret = SyncML::APIReturn->new;
    $ret->ok(1);

    my $cu = $self->_get_rt_current_user($username);

    my $ticket = RT::Ticket->new($cu);
    $ticket->Load($syncable_item->application_identifier);

    unless ($ticket->Id) {
        $self->log->warn("Failed to load ticket '", $syncable_item->application_identifier, "'");
        $ret->ok(0);
        return $ret;
    }

    if ($status eq 'COMPLETED') {
        # They're trying to check off an item; we need to set it to resolved.

        my ($ok, $msg);
        if ($just_checking) {
            $ok = $ticket->CurrentUserHasRight('ModifyTicket');
        } else {
            ($ok, $msg) = $ticket->Resolve;
        }

        $ret->ok($ok);
        $ret->delete_this(1) if $ok;
    } else {
        if ($just_checking) {
            # We need to make sure they get RT's version of the ticket (with the nice report in
            # the description, etc).  (Only during package 3 ("just checking" phase), because 
            # that's when we can actually talk back to the client.)

            $ret->replace_with($self->_syncable_for_ticket($ticket));
        }
    } 

    return $ret;
} 

sub delete_item {
    my $self = shift;
    my $dbname = shift; # ignored for now
    my $application_identifier = shift;
    my $username = shift;
    my $just_checking = shift;

    my $cu = $self->_get_rt_current_user($username);

    my $ticket = RT::Ticket->new($cu);
    $ticket->Load($application_identifier);

    unless ($ticket->Id) {
        $self->log->warn("Failed to load ticket '$application_identifier'");
        return;
    } 
    
    my ($ok, $msg);
    if ($just_checking) {
        $ok = $ticket->CurrentUserHasRight('ModifyTicket');
    } else {
        ($ok, $msg) = $ticket->Reject;
    }

    return $ok ? 1 : 0;
}

sub add_item {
    my $self = shift;
    my $dbname = shift; # ignored for now
    my $syncable_item = shift;
    my $username = shift;
    my $just_checking = shift;

    my $cu = $self->_get_rt_current_user($username);
    my $q = $self->_get_queue($cu);

    my $ic = $syncable_item->content_as_object;

    my ($ok, $application_id);
    if ($just_checking) {
        $ok = $cu->HasRight(Right => 'CreateTicket', Object => $q) and
              $cu->HasRight(Right => 'OwnTicket',    Object => $q);
    } else {
        my $ticket = RT::Ticket->new($cu);
        $ticket->Create( Queue => $q->id, 
            Subject => $ic->entries->[0]->property("summary")->[0]->value,
            Owner => $cu->Id);
        # Put in LastUpdated too?
        $application_id = $ticket->Id;
        $ok = $application_id != 0;
    }

    return ($ok, $application_id);
}

1;
