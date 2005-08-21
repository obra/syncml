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

my %COMMAND_HANDLERS = (
    Alert   => 'handle_alert',
    Sync    => 'handle_sync',
    Map     => 'handle_map',
    Get     => 'handle_get',
    Add     => 'handle_add_or_replace',
    Replace => 'handle_add_or_replace',
);

my %POST_SUBCOMMAND_HANDLERS = ( Sync => 'handle_ps_sync', );

sub new {
    my $class = shift;
    my $self  = bless {}, $class;

    $self->last_message_id(0);
    $self->anchor(0);

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

    $self->add_status_for_header(200);

    for my $command ( @{ $in_message->commands } ) {
        $self->respond_to_command($command);
    }

    return $out_message;
}

sub respond_to_command {
    my $self    = shift;
    my $command = shift;

    return if $command->command_name eq 'Status';

    # The following method call inserts the status object into the output
    # message. But note that if you later modify the status object, the
    # modification will in fact show up in the output message (as you'd
    # hope).
    my $status = $self->add_status_for_command($command);

    if ( my $handler = $COMMAND_HANDLERS{ $command->command_name } ) {
        $self->$handler( $command, $status );
    } else {
        $status->status_code(200);
    }

    for my $subcommand ( @{ $command->subcommands } ) {
        $self->respond_to_command($subcommand);
    }

    if ( my $handler = $POST_SUBCOMMAND_HANDLERS{ $command->command_name } ) {
        $self->$handler($command);
    }
}

sub add_status_for_header {
    my $self        = shift;
    my $status_code = shift;

    my $status = SyncML::Message::Command->new;
    $status->command_name('Status');
    $self->out_message->stamp_command_id($status);

    $status->message_reference( $self->in_message->message_id );
    $status->command_reference('0');
    $status->command_name_reference('SyncHdr');

    $status->target_reference( $self->in_message->target_uri );
    $status->source_reference( $self->in_message->source_uri );

    $status->status_code($status_code);

    push @{ $self->out_message->commands }, $status;
    return;
}

sub add_status_for_command {
    my $self    = shift;
    my $command = shift;

    my $status = SyncML::Message::Command->new;
    $status->command_name('Status');
    $self->out_message->stamp_command_id($status);

    $status->message_reference( $self->in_message->message_id );
    $status->command_reference( $command->command_id );
    $status->command_name_reference( $command->command_name );

    $status->target_reference( $command->target_uri )
        if defined_and_length( $command->target_uri );
    $status->source_reference( $command->source_uri )
        if defined_and_length( $command->source_uri );

    push @{ $self->out_message->commands }, $status;
    return $status;
}

sub _generate_internal_session_id {
    my $self = shift;

    $self->internal_session_id( Digest::MD5::md5_hex(rand) );
}

sub handle_alert {
    my $self    = shift;
    my $command = shift;
    my $status  = shift;

    $status->status_code(200);

    unless ( @{ $command->items } == 1
        and ( $command->alert_code == 200 or $command->alert_code == 201 ) )
    {
        warn "items or alert code wrong";
        $status->status_code(500);
        return;
    }

    my $item = $command->items->[0];

    push @{ $status->items },
        { meta => { AnchorNext => $item->{'meta'}->{'AnchorNext'} } };

    my $response_alert = SyncML::Message::Command->new;
    $response_alert->command_name('Alert');
    $self->out_message->stamp_command_id($response_alert);
    push @{ $self->out_message->commands }, $response_alert;
    $response_alert->alert_code('201');    # slow sync
    my $last_anchor = $self->anchor;
    $self->anchor(time);
    push @{ $response_alert->items },
        {
        meta => { AnchorNext => $self->anchor, AnchorLast => $last_anchor },
        source_uri => $item->{'target_uri'},
        target_uri => $item->{'source_uri'},
        };
}

sub handle_get {
    my $self    = shift;
    my $command = shift;
    my $status  = shift;

    $status->status_code(200);

    my $results = SyncML::Message::Command->new('Results');
    $self->out_message->stamp_command_id($results);

    $results->message_reference( $self->in_message->message_id );
    $results->command_reference( $command->command_id );

    $results->target_reference( $command->target_uri )
        if defined_and_length( $command->target_uri );
    $results->source_reference( $command->source_uri )
        if defined_and_length( $command->source_uri );

    $results->source_uri('./devinf11');

    $results->include_device_info(1);

    push @{ $self->out_message->commands }, $results;
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

# If they're sending a Sync, that means we need to send a Sync back.
# This handler isn't actually going to handle the subcommands of the client
# Sync yet; for now we'll just have it add our Sync.
sub handle_sync {
    my $self    = shift;
    my $command = shift;
    my $status  = shift;

    $status->status_code(200);

    my $response_sync = SyncML::Message::Command->new('Sync');
    $self->out_message->stamp_command_id($response_sync);
    push @{ $self->out_message->commands }, $response_sync;
    $response_sync->target_uri( $command->source_uri );
    $response_sync->source_uri( $command->target_uri );

    $self->response_sync($response_sync);

   # Clear out our understanding of the client's database, which we'll restore
   # from its slow sync response in handle_add_or_replace
    $self->client_database( {} );
}

sub handle_add_or_replace {
    my $self    = shift;
    my $command = shift;
    my $status  = shift;

    for my $item ( @{ $command->items } ) {
        my $content   = $item->{'data'};
        my $client_id = $item->{'source_uri'};

        unless ( defined $client_id and length $client_id ) {
            warn "told to add/replace an item, but no client id!";
            next;
        }

        my $syncdb_entry = SyncML::SyncDBEntry->new;
        $syncdb_entry->content($content);
        $syncdb_entry->type("text/calendar");
        $syncdb_entry->client_identifier($client_id);

      # I'm not setting the application ID yet, even though it might be in the
      # sync DB... not sure where the right place to do that is (currently in
      # handle_ps_sync, but that feels wrong)

        $self->client_database->{$client_id} = $syncdb_entry;
    }

    $status->status_code(200);
}

sub handle_ps_sync {
    my $self    = shift;
    my $command = shift;

    my $response_sync = $self->response_sync;
    $self->get_unchanged_dead_future_changed;

    # We're going to build up an understanding of what the synchronized state
    # should be at the end of this transaction in synced_state.  This is
    # a hash of SyncDBEntrys, indexed by client ID (LUID).  Server additions
    # will go into waiting_for_map (also as SyncDBEntrys), indexed by
    # application ID, since they don't have a client ID until after the server
    # receives the Map command in package #5 (at that point they'll be moved
    # into synced_state).
    $self->synced_state(    {} );
    $self->waiting_for_map( {} );

    # Look at the things we haven't touched.  For these, whatever the client
    # says goes.
    for my $client_id ( keys %{ $self->unchanged } ) {
        if ( my $syncdb_entry = delete $self->client_database->{$client_id} )
        {

          # client has it.  so do we, and we haven't changed it.  so we should
          # make sure that the server ends up with whatever the client has.

          # syncdb entries in client_database don't have app IDs yet (possibly
          # this is poor design)
            $syncdb_entry->application_identifier(
                $self->unchanged->{$client_id}->application_identifier );
            $self->synced_state->{$client_id} = $syncdb_entry;
        } else {

            # We have it, client doesn't.  Clearly the client deleted it.
            # We should, too. So we don't put it into synced_state.
            # ... do nothing ...
        }
    }

    # Look at the things we've modified.  For these, our change will beat a
    # client deletion.  For now, our change will always beat a client change,
    # but really this should be doing field-by-field merge.
    for my $client_id ( keys %{ $self->changed } ) {
        my $server_syncdb_entry = $self->changed->{$client_id};

        my $client_syncdb_entry = delete $self->client_database->{$client_id};

       # Whether or not they've deleted it, the server now wins.  In lieu of a
       # real field-by-field merge support, just send out a Replace from us.

        my $replace = SyncML::Message::Command->new('Replace');
        $self->out_message->stamp_command_id($replace);

        push @{ $replace->items },
            {
            target_uri => $client_id,
            data       => $server_syncdb_entry->content,
            };
        $replace->meta_hash( { Type => $server_syncdb_entry->type, } );
        push @{ $response_sync->subcommands }, $replace;

        $self->synced_state->{$client_id} = $server_syncdb_entry;
    }

    # Deal with server-side adds.  (These are easy, since there's no conflict
    # possible, since there isn't a client ID for them yet!)
    for my $application_id ( keys %{ $self->future } ) {
        my $syncable_item = $self->future->{$application_id};

        my $syncdb_entry = SyncML::SyncDBEntry->new;
        $syncdb_entry->application_identifier($application_id);
        $syncdb_entry->content( $syncable_item->content );
        $syncdb_entry->type( $syncable_item->type );

        my $add = SyncML::Message::Command->new('Add');
        $self->out_message->stamp_command_id($add);

        push @{ $add->items },
            {
            source_uri => $application_id,
            data       => $syncdb_entry->content,
            };
        $add->meta_hash( { Type => $syncdb_entry->type, } );
        push @{ $response_sync->subcommands }, $add;

        $self->waiting_for_map->{$application_id} = $syncdb_entry;
    }

    # Deal with server-side deletes.  If the client has touched it, then we
    # forget about the delete and process the client's replace instead.
    # Otherwise we send a Delete to the client.
    for my $client_id ( keys %{ $self->dead } ) {
        my $server_syncdb_entry = $self->dead->{$client_id};

        if ( my $client_syncdb_entry
            = delete $self->client_database->{$client_id} )
        {
            if (    $client_syncdb_entry->type eq $server_syncdb_entry->type
                and $client_syncdb_entry->content eq
                $server_syncdb_entry->content )
            {

              # The client hasn't changed it, but we've deleted it.  Send them
              # a delete command.
                my $delete = SyncML::Message::Command->new('Delete');
                $self->out_message->stamp_command_id($delete);

                push @{ $delete->items }, { target_uri => $client_id, };
                push @{ $response_sync->subcommands }, $delete;

                # Don't save anything to synced_state.
            } else {

                # The client changed it.  Just forget about our attempt at
                # delete and save what the client wants.

                $client_syncdb_entry->application_identifier(
                    $server_syncdb_entry->application_identifier );

                $self->synced_state->{$client_id} = $client_syncdb_entry;
            }
        } else {

            # We deleted it, the client deleted it.  We don't have to do
            # anything!
        }
    }

    # Everything in client_database that the server thought the client had
    # before has now been deleted from it.  Thus anything left in
    # client_database should now count as a client addition.

    for my $client_id ( keys %{ $self->client_database } ) {
        my $client_syncdb_entry = $self->client_database->{$client_id};

        # Note that this SyncDBEntry has undefined application_identifier.

        $self->synced_state->{$client_id} = $client_syncdb_entry;
    }
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
    my $database_info
        = YAML::LoadFile($SYNC_DATABASE)->{'devicename-username-dbname'};

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

# this method has a really stupid name, mostly because it will die soon after
# being written
sub get_unchanged_dead_future_changed {
    my $self = shift;

    my $sync_db = $self->get_sync_database;
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

    # initialize the hashes
    $self->$_( {} ) for qw/unchanged dead future changed/;

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
                $self->changed->{$client_id} = $sync_db_entry;
            } else {

                # Yes, and we haven't touched it.
                $self->unchanged->{$client_id} = $sync_db_entry;
            }
        } else {

            # Nope, must have deleted it.
            $self->dead->{$client_id} = $sync_db_entry;
        }
    }

   # For each of the entries that we have but that the client didn't have last
   # time (ie, that weren't hit by the 'delete' above)
    while ( my ( $application_id, $syncable_item ) = each %$app_db ) {
        $self->future->{$application_id} = $syncable_item;
    }

    warn "sorted: " . YAML::Dump $self;
}

__PACKAGE__->mk_accessors(
    qw/session_id internal_session_id last_message_id uri_base in_message out_message
        anchor done client_database response_sync

        my_last_anchor client_last_anchor last_sync_seconds

        unchanged dead future changed original_synced_state synced_state waiting_for_map/
);

# note that unchanged and changed and dead are hashes of SyncDBEntrys, whereas
# future is a hash of SyncableItems

sub defined_and_length { defined $_[0] and length $_[0] }

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

1;
