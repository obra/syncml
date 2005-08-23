package SyncML::Engine;

use warnings;
use strict;

use base qw/Class::Accessor/;

use Carp;
use SyncML::Message;
use SyncML::Message::Command;
use SyncML::SyncableItem;
use SyncML::SyncDBEntry;
use Digest::MD5;
use MIME::Base64 ();
use YAML         ();

use Data::ICal;
use Data::ICal::Entry::Todo;

use FindBin;
my $APPLICATION_DATABASE = "eg/database";
my $SYNC_DATABASE        = "eg/syncdb";

=head1 NAME

SyncML::Engine - Represents the state of a SyncML transaction


=head1 SYNOPSIS

    use SyncML::Engine;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.
  
  
=head1 DESCRIPTION


=head1 METHODS

=head2 new

Creates a new L<SyncML::Engine>.

=cut

my $PACKAGE_HANDLERS = {
    1 => 'handle_client_initialization',
    3 => 'handle_client_modifications',
    5 => 'handle_client_mapping',
}; 

sub new {
    my $class = shift;
    my $self  = bless {}, $class;

    $self->last_message_id(0);
    $self->anchor(0);

    $self->current_package(1);

    $self->_generate_internal_session_id;

    return $self;
}

sub respond_to_message {
    my $self       = shift;
    my $in_message = shift;

    my $out_message = SyncML::Message->new;

    $self->in_message($in_message);
    $self->out_message($out_message);

    warn "Weird: session ID is different"
        if defined $self->session_id
        and $in_message->session_id ne $self->session_id;
    $self->session_id( $in_message->session_id );
    $out_message->session_id( $in_message->session_id );

    $self->last_message_id( $self->last_message_id + 1 );
    $out_message->message_id( $self->last_message_id );

    $out_message->response_uri(
        $self->uri_base . "?sid=" . $self->internal_session_id );

    $out_message->source_uri( $in_message->target_uri );
    $out_message->target_uri( $in_message->source_uri );

    $self->device_uri($in_message->source_uri);

    if (not defined $in_message->basic_authentication) {
        $self->add_status_for_header(401);

        for my $command (@{ $self->in_message->commands }) {
            $self->add_status_for_command($command)->status_code(401);
        } 
    } elsif ($self->authenticated($in_message->basic_authentication)) {
        $self->add_status_for_header(200);

        my $package_handler = $PACKAGE_HANDLERS->{$self->current_package};
        $self->$package_handler;
    } else {
        $self->add_status_for_header(407);

        for my $command (@{ $self->in_message->commands }) {
            $self->add_status_for_command($command)->status_code(407);
        } 
    } 
    

    warn "didn't send a status to everything" unless $in_message->sent_all_status;

    return $out_message;
}

sub add_status_for_header {
    my $self        = shift;
    my $status_code = shift;

    my $status = SyncML::Message::Command::Status->new;
    $self->out_message->stamp_command_id($status);

    $status->message_reference( $self->in_message->message_id );
    $status->command_reference('0');
    $status->command_name_reference('SyncHdr');

    $status->target_reference( $self->in_message->target_uri );
    $status->source_reference( $self->in_message->source_uri );

    $status->status_code($status_code);

    $status->include_basic_challenge(1) if $status_code == 407 or $status_code == 401;

    $self->in_message->response_status_for_header($status);

    push @{ $self->out_message->commands }, $status;
    return;
}

sub add_status_for_command {
    my $self    = shift;
    my $command = shift;

    my $status = SyncML::Message::Command::Status->new;
    $self->out_message->stamp_command_id($status);

    $status->message_reference( $self->in_message->message_id );
    $status->command_reference( $command->command_id );
    $status->command_name_reference( $command->command_name );

    $status->target_reference( $command->target_uri )
        if defined $command->target_uri;
    $status->source_reference( $command->source_uri )
        if defined $command->source_uri;

    $command->response_status($status);

    push @{ $self->out_message->commands }, $status;
    return $status;
}

sub _generate_internal_session_id {
    my $self = shift;

    $self->internal_session_id( Digest::MD5::md5_hex(rand) );
}

sub authenticated {
    my $self = shift;
    my $user_password = shift;
    
    return unless defined $user_password;

    my ($user, $password) = $user_password =~ /\A ([^:]*) : (.*) \z/xms;

    return unless defined $user;

    my $syncdb = YAML::LoadFile($SYNC_DATABASE);

    return unless $syncdb;
    return unless $syncdb->{$user};
    return unless $syncdb->{$user}{'password'} eq $password;

    $self->authenticated_user($user);

    return 1;
} 

sub handle_client_initialization {
    my $self = shift;

    # We're in package #1 -- client initialization.
    # It should contain (in addition to authentication info in the header):
    #
    #  * An Alert for each database that the client wants to synchronize (with
    #    sync anchors)
    #  * Possibly a Put of device capabilities.
    #  * Possibly a Get of device capabilities.
    #
    #  Our response is package #2 -- server initialization.
    #  It should contain:
    #  * Status for the SyncHdr
    #  * Status for the Alert (with a repetition of the client's Next anchor) 
    #  * Status for the Put, if received 
    #  * Results (device info) for the Get, if received 
    #  * Alert for each database to be sychronized (with the alert code that
    #    will be used -- can be different from the client's choice; and the
    #    server's Next and Last anchors)
    
    for my $alert ($self->in_message->commands_named('Alert')) {
        my $status = $self->add_status_for_command($alert);
        $self->handle_client_init_alert($alert, $status);
    } 

    for my $put ($self->in_message->commands_named('Put')) {
        warn "strange put found" unless $put->source_uri eq './devinf11';
        $self->add_status_for_command($put)->status_code(200);
    } 

    for my $get ($self->in_message->commands_named('Get')) {
        my $status = $self->add_status_for_command($get);
        $self->handle_get($get, $status);
    } 

    unless ($self->in_message->final) {
        # XXX TODO FIXME
        warn "multi-message packages not yet supported!";
    } 

    $self->current_package(3);
} 

sub handle_client_modifications {
    my $self = shift;

    # We're in package #3 -- client modifications.
    # It should contain:
    #
    #  * Status for server Alerts
    #  * Status for Put, if Put sent
    #  * Results, if Get sent
    #  * Sync for each database being synchronized, containing:
    #      * Add, Replace, and Delete commands.
    #        (note: we're doing slow sync, so this is just going to
    #         be Replace commands, or maybe equivalent Adds)
    #  
    #  Our response is package #4 -- server modifications.
    #  It should contains:
    #
    #  * Status for Sync and its subcommands
    #  * A Sync containing Adds, Replaces, Deletes
   
    for my $sync ($self->in_message->commands_named('Sync')) {
        my $status = $self->add_status_for_command($sync);
        $self->handle_client_sync($sync, $status);
    } 

    unless ($self->in_message->final) {
        # XXX TODO FIXME
        warn "multi-message packages not yet supported!";
    } 

    $self->current_package(5);
} 

sub handle_client_init_alert {
    my $self    = shift;
    my $alert_in = shift;
    my $status  = shift;

    $status->status_code(200);

    unless ( $alert_in->alert_code == 200 or $alert_in->alert_code == 201 )
    {
        warn "alert code unknown: @{[ $alert_in->alert_code ]}";
        $status->status_code(500);
        return;
    }

    # Copy the Next anchor from the Alert to its Status
    $status->next_anchor_acknowledgement( $alert_in->next_anchor );

    # Create a response alert
    my $alert_out = SyncML::Message::Command::Alert->new;
    $self->out_message->stamp_command_id($alert_out);
    push @{ $self->out_message->commands }, $alert_out;

    # For now, let's always Slow Sync
    $alert_out->alert_code('201');    # slow sync

    # XXX This anchor-choosing algorithm is wrong; we should be pulling it
    #     from the SyncDB
    my $last_anchor = $self->anchor;
    $self->anchor(time);

    $alert_out->last_anchor($last_anchor);
    $alert_out->next_anchor($self->anchor);
    $alert_out->target_db_uri($alert_in->source_db_uri);
    $alert_out->source_db_uri($alert_in->target_db_uri);
}

sub handle_client_sync {
    my $self    = shift;
    my $sync_in = shift;
    my $sync_status  = shift;

    $sync_status->status_code(200);

    my $client_db = $sync_in->source_uri;
    my $server_db = $sync_in->target_uri;

    my $syncdb = $self->get_sync_database($server_db);
    
    unless ($syncdb) {
        $sync_status->status_code(404);
        for my $command (@{ $sync_in->subcommands }) {
            $self->add_status_for_command($command)->status_code(404);
        } 
        return;
    } 

    # $client_database is a hash of SyncDBEntrys indexed by client_identifier.
    # It represents what the client is saying it has *right now*.
    my $client_database = {};

    # Since we're in Slow Sync, the subcommands of the Sync ought to be Replaces
    for my $replace (@{ $sync_in->subcommands }) {
        unless ($replace->isa('SyncML::Message::Command::Replace')) {
            warn "non-Replace subcommand found in slow sync: $replace";
            next;
        } 

        # Note that this SyncDBEntry's application_identifier is not yet set
        my $syncdb_entry = $replace->syncdb_entry;

        $client_database->{ $syncdb_entry->client_identifier } = $syncdb_entry;

        my $subcommand_status = $self->add_status_for_command($replace);
        $subcommand_status->status_code(200); # XXX if interpreted as an add, should be 201
    } 

    my $diff = $self->get_server_differences($syncdb); 

    # We're going to build up an understanding of what the synchronized state
    # should be at the end of this transaction in synced_state.  This is a hash
    # of SyncDBEntrys, indexed by client ID (LUID).  Server additions will go
    # into waiting_for_map (also as SyncDBEntrys), indexed by application ID,
    # since they don't have a client ID until after the server receives the Map
    # command in package #5 (at that point they'll be moved into synced_state).
    my $synced_state;
    my $waiting_for_map;

    # Create a response Sync
    my $sync_out = SyncML::Message::Command::Sync->new;
    $self->out_message->stamp_command_id($sync_out);
    push @{ $self->out_message->commands }, $sync_out;

    $sync_out->target_uri($sync_in->source_uri);
    $sync_out->source_uri($sync_in->target_uri);

    # Look at the things we haven't touched.  For these, whatever the client
    # says goes.
    for my $client_id ( keys %{ $diff->unchanged } ) {
        if ( my $syncdb_entry = delete $client_database->{$client_id} )
        {
          # client has it.  so do we, and we haven't changed it.  so we should
          # make sure that the server ends up with whatever the client has.

          # syncdb entries in client_database don't have app IDs yet (possibly
          # this is poor design)
            $syncdb_entry->application_identifier(
                $diff->unchanged->{$client_id}->application_identifier );
            $synced_state->{$client_id} = $syncdb_entry;
        } else {

            # We have it, client doesn't.  Clearly the client deleted it.
            # We should, too. So we don't put it into synced_state.
            # ... do nothing ...
        }
    }

    # Look at the things we've modified.  For these, our change will beat a
    # client deletion.  For now, our change will always beat a client change,
    # but really this should be doing field-by-field merge.
    for my $client_id ( keys %{ $diff->changed } ) {
        my $server_syncdb_entry = $diff->changed->{$client_id};

        my $client_syncdb_entry = delete $client_database->{$client_id};

       # Whether or not they've deleted it, the server now wins.  In lieu of a
       # real field-by-field merge support, just send out a Replace from us.

        my $replace = SyncML::Message::Command::Replace->new;
        $self->out_message->stamp_command_id($replace);

        $replace->syncdb_entry($server_syncdb_entry->clone);

        push @{ $sync_out->subcommands }, $replace;

        $synced_state->{$client_id} = $server_syncdb_entry;
    }

    # Deal with server-side adds.  (These are easy, since there's no conflict
    # possible, since there isn't a client ID for them yet!)
    for my $application_id ( keys %{ $diff->future } ) {
        my $syncable_item = $diff->future->{$application_id};

        my $syncdb_entry = SyncML::SyncDBEntry->new;
        $syncdb_entry->application_identifier($application_id);
        $syncdb_entry->content( $syncable_item->content );
        $syncdb_entry->type( $syncable_item->type );

        my $add = SyncML::Message::Command::Add->new;
        $self->out_message->stamp_command_id($add);

        $add->syncdb_entry($syncdb_entry->clone);

        push @{ $sync_out->subcommands }, $add;

        $waiting_for_map->{$application_id} = $syncdb_entry;
    }

    # Deal with server-side deletes.  If the client has touched it, then we
    # forget about the delete and process the client's replace instead.
    # Otherwise we send a Delete to the client.
    for my $client_id ( keys %{ $diff->dead } ) {
        my $server_syncdb_entry = $diff->dead->{$client_id};

        if ( my $client_syncdb_entry
            = delete $client_database->{$client_id} )
        {
            if (    $client_syncdb_entry->type eq $server_syncdb_entry->type
                and $client_syncdb_entry->content eq
                $server_syncdb_entry->content )
            {

              # The client hasn't changed it, but we've deleted it.  Send them
              # a delete command.
                my $delete = SyncML::Message::Command::Delete->new;
                $self->out_message->stamp_command_id($delete);
                $delete->client_identifier($client_id);

                push @{ $sync_out->subcommands }, $delete;

                # Don't save anything to synced_state.
            } else {

                # The client changed it.  Just forget about our attempt at
                # delete and save what the client wants.

                $client_syncdb_entry->application_identifier(
                    $server_syncdb_entry->application_identifier );

                $synced_state->{$client_id} = $client_syncdb_entry;
            }
        } else {

            # We deleted it, the client deleted it.  We don't have to do
            # anything!
        }
    }

    # Everything in client_database that the server thought the client had
    # before has now been deleted from it.  Thus anything left in
    # client_database should now count as a client addition.

    for my $client_id ( keys %$client_database ) {
        my $client_syncdb_entry = $client_database->{$client_id};

        # Note that this SyncDBEntry has undefined application_identifier.

        $synced_state->{$client_id} = $client_syncdb_entry;
    }

    warn "synced state: ".YAML::Dump($synced_state);
    warn "wfm: ".YAML::Dump($waiting_for_map);
}

sub handle_get {
    my $self    = shift;
    my $command = shift;
    my $status  = shift;

    unless ($command->target_uri eq './devinf11') {
        warn "strange get found: '@{[ $command->source_uri ]}'";
        $status->status_code(401);
    } else {
        # We know how to deal with devinf11; success.
        $status->status_code(200);

        # Make a Results object.
        # Note that S::M::C::Results is hardcoded to include the appropriate
        # device info.
        my $results = SyncML::Message::Command::Results->new;
        $self->out_message->stamp_command_id($results);
        push @{ $self->out_message->commands }, $results;

        $results->message_reference( $self->in_message->message_id );
        $results->command_reference( $command->command_id );
    } 
}

sub handle_map {
    my $self    = shift;
    my $command = shift;
    my $status  = shift;

    my $db;

  # Map commands happen only in the final package, so mark the engine as done.
    $self->done(1);

    for my $item ( @{ $command->items } ) {
        my $client_id      = $item->{source_uri};
        my $application_id = $item->{target_uri};

        if ( my $syncdb_entry
            = delete $self->waiting_for_map->{$application_id} )
        {
            $syncdb_entry->client_identifier($client_id);
            $self->synced_state->{$client_id} = $syncdb_entry;
        } else {
            warn
                "client wants to tell us its id ($client_id) for a new record with app id '$application_id', but we weren't expecting that!";
        }
    }

    for my $application_id ( keys %{ $self->waiting_for_map } ) {
        warn
            "failed to get client map response for item with app id '$application_id'... I guess we'll lose it";
    }

    $self->merge_back_to_server;

    $status->status_code(200);
}

# At this point original_synced_state represents the agreed synchronization from
# last time, and synced_state represents the agreed synchronization from now.
# Now we diff them, apply the changes to the app database, and save the sync
# database.
#
# This is somewhat backwards -- the database ought to be able to refuse
# operations in the merge, which should cause different results in Statuses
# we've already sent out.  Eit.  This should be fixed when we rewrite the Engine
# to be more of a state machine than a callback handler.
sub merge_back_to_server {
    my $self = shift;

    warn "Original agreed state was: "
        . YAML::Dump $self->original_synced_state;
    warn "Current agreed state is: " . YAML::Dump $self->synced_state;
    exit;

    # ...
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

sub save_application_database {
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

sub get_sync_database {
    my $self = shift;
    my $dbname = shift;

    my $syncdb = YAML::LoadFile($SYNC_DATABASE);
    return unless my $database_info = $syncdb->{$self->authenticated_user}{'devices'}{$self->device_uri}{$dbname};

    $self->$_( $database_info->{$_} )
        for qw/my_last_anchor client_last_anchor last_sync_seconds/;

    my $db = $database_info->{db};

    for my $client_id ( keys %$db ) {
        my $info = $db->{$client_id};

        my $syncdb = SyncML::SyncDBEntry->new;

        $syncdb->application_identifier( $info->{application_identifier} );
        $syncdb->content( $info->{content} );
        $syncdb->type( $info->{type} );
        $syncdb->client_identifier($client_id);

        $db->{$client_id} = $syncdb;
    }

    return $db;
}

sub save_sync_database {
    my $self = shift;
    my $db   = shift;

    my $outdb = {};

    for my $client_id ( keys %$db ) {
        my $syncdb = $db->{$client_id};

        $outdb->{$client_id} = { map { $_ => $syncdb->$_ }
                qw/application_identifier content type/ };
    }

    my $database_info = {};
    $database_info->{$_} = $self->$_
        for qw/my_last_anchor client_last_anchor last_sync_seconds/;
    $database_info->{db} = $outdb;
    YAML::DumpFile( $SYNC_DATABASE,
        { 'devicename-username-dbname' => $database_info } );
}

sub get_server_differences {
    my $self = shift;
    my $sync_db = shift;

    $self->original_synced_state($sync_db);
    my $app_db = $self->get_application_database;

  # go through app db put things in either unchanged changed or future
  # depending on existence in sync db and timestamp; delete from sync db while
  # going on
  #
  # put the rest of sync db in dead
  #
  # but what should the contents of these fields be?  well, we'll still need
  # LUID but won't need last-mod, so obviously they should be SyncDBEntrys
  #
  # so maybe actually what needs to be done is:

    my $diff = SyncML::Engine::ServerDiff->new;

    # For each of the entries that the client had last time we heard from
    # them...
    for my $client_id ( keys %$sync_db ) {
        my $sync_db_entry = $sync_db->{$client_id};

        # Do we still have it?
        if ( my $syncable_item
            = delete $app_db->{ $sync_db_entry->application_identifier } )
        {
            if ( $syncable_item->last_modified_as_seconds
                > $self->last_sync_seconds )
            {

                # Yes, but it's been dirtied.
                $diff->changed->{$client_id} = $sync_db_entry;
            } else {

                # Yes, and we haven't touched it.
                $diff->unchanged->{$client_id} = $sync_db_entry;
            }
        } else {

            # Nope, must have deleted it.
            $diff->dead->{$client_id} = $sync_db_entry;
        }
    }

   # For each of the entries that we have but that the client didn't have last
   # time (ie, that weren't hit by the 'delete' above)
    while ( my ( $application_id, $syncable_item ) = each %$app_db ) {
        $diff->future->{$application_id} = $syncable_item;
    }

    warn "diff: " . YAML::Dump $diff;

    return $diff;
}

# current_package has legal values 1, 3, or 5 -- represents the current package
# that we're responding to. 1 is client initialization, 3 is client changes, 5
# is mapping.

__PACKAGE__->mk_accessors(
    qw/session_id internal_session_id last_message_id uri_base in_message out_message
        anchor done 

	current_package

    authenticated_user device_uri

        my_last_anchor client_last_anchor last_sync_seconds

        unchanged dead future changed original_synced_state/
);

# note that unchanged and changed and dead are hashes of SyncDBEntrys, whereas
# future is a hash of SyncableItems


=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.
  
SyncML::Message requires no configuration files or environment variables.


=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-syncml-message@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

David Glasser  C<< <glasser@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2005, Best Practical Solutions, LLC.  All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=cut

package SyncML::Engine::ServerDiff;
use base qw/Class::Accessor/;
__PACKAGE__->mk_accessors(qw/unchanged dead future changed/);

sub new {
    my $class = shift;
    my $self = {};
    $self->{$_} = {} for qw/unchanged dead future changed/;
    return bless $self, $class;
} 

1;
