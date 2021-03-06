package SyncML::Message::Command;

use warnings;
use strict;

use base qw/Class::Accessor/;

use Carp;
use XML::Twig;

=head1 NAME

SyncML::Message::Command - Abstract base class for a single (possibly compound) SyncML command


=head1 SYNOPSIS

    use SyncML::Message::Command;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.
  
  
=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.


=head1 METHODS

=cut

=head2 command_name

Gets the SyncML command name, such as C<Add>, C<Status>, or C<Sync>.  (Implemented 
in the subclass.)

=head2 command_id [$command_id]

(Required.) Gets or sets the command ID for the command, a non-empty, non-C<"0"> text value.

=head2 no_response [$no_response]

Gets or sets a boolean flag (defaults to false) indicating that the recipient must not send
a C<Status> for this command.

=head2 credentials

XXX TODO FIXME

=head2 subcommands

Returns an array reference to the subcommands of this command, for commands like C<Sync> or C<Atomic>.

=head2 target_uri [$target_uri]

(Required for C<Map> and C<Sync>.) Gets or sets the URI of the target database of this message.  
This can be relative to the target specified in the message header, or absolute.

=head2 source_uri [$source_uri]

(Required for C<Map> and C<Sync>.) Gets or sets the URI of the source database of this message.  
This can be relative to the source specified in the message header, or absolute.

=head2 message_reference [$message_reference]

(Required for C<Status> and C<Results>.)  Gets or sets the message ID that this command is in response to.

=head2 command_reference [$command_reference]

(Required for C<Status> and C<Results>.)  Gets or sets the command ID that this command is in response to.

=head2 command_name_reference [$command_name_reference]

(Required for C<Status>.) Gets or sets the command name that this status is in response to.

=head2 target_reference [$target_reference]

(Optional for C<Status>.) Gets or sets the target URI that this status is in response to.

XXX TODO FIXME multiple target refs?

=head2 source_reference [$source_reference]

(Optional for C<Status>.) Gets or sets the source URI that this status is in response to.

XXX TODO FIXME multiple source refs?

=head2 status_code [$status_code]

(Required for C<Status>.) Gets or sets the numeric status code of this status (the C<< <Data> >> element).

=head2 alert_code [$alert_code]

(Required for C<Alert>.) Gets or sets the numeric code of this alert (the C<< <Data> >> element).

=head2 challenge

XXX TODO FIXME

=cut

__PACKAGE__->mk_accessors(
    qw/command_id no_response target_uri source_uri response_status/
);

=head2 sent_all_status

Returns a boolean telling whether or not it hasn't had a status command
created for it yet.  (Commands with subcommands should override this
method to check their subcommands for status too.)

=cut

sub sent_all_status {
    my $self = shift;

    return 1 if $self->no_response;

    return unless $self->response_status;

    return 1;
}

=head2 new

Creates a new L<SyncML::Message::Command>; should only be called via a subclass.

=cut

sub new {
    my $class = shift;
    my $self  = bless {}, $class;
    
    return $self;
}

=head2 as_xml

Returns the command as an XML string.

A key part of the design here is that C<as_xml> is only expected to be able
to render the actual commands that we make as XML.  That is, any command that
we build (at a high level) should be able to be represented as XML with C<as_xml>,
but we should not strive for it to be able to generate arbitrary well-formed 
SyncML.  (That is, a L<SyncML::Message::Command> object is expected to be
a high-level representation of the command that our code can deal with, not to be
a container for arbitrary SyncML code.)

=cut

sub as_xml {
    my $self = shift;

    my $x = XML::Builder->new;

    $x->_elt(
        $self->command_name,
        sub {
            $x->CmdID( $self->command_id );
            $x->NoResp if $self->no_response;

            $self->_build_xml_body($x);
        }
    );

    return $x->_output;
}

sub _build_xml_body {
    my $self = shift;
    my $builder = shift;
    # Do nothing. Subclasses do fun stuff here.
} 

=head2 from_xml $string

Parses the XML document C<$string> representing a command into the object.
Should only be called once on any given object.

A key part of the design here is that C<as_xml> is only expected to be able
to render the actual commands that we make as XML.  That is, any command that
we build (at a high level) should be able to be represented as XML with C<as_xml>,
but we should not strive for it to be able to generate arbitrary well-formed 
SyncML.

=cut

sub from_xml {
    my $self = shift;
    my $text  = shift;

    if ($self->{'__parsed__'}++) {
        die "from_xml called twice on the same object!";
    } 

    my $twig = XML::Twig->new;
    $twig->parse($text);

    $self->_from_twig( $twig->root );
    return;
}

sub _from_twig {
    my $self   = shift;
    my $twig = shift;

    $self->command_id( $twig->slimmed_field('CmdID') );
    $self->no_response( $twig->has_child('NoResp') ? 1 : 0 );

    return;
}


=head2 supported_commands 

Returns a list of names of supported SyncML commands.

=cut

my @_SUPPORTED_COMMANDS = qw(    
        Alert  Copy  Exec  Get  Map  Put  Results  Search  Status  Sync  Add  Replace  Delete
);

sub supported_commands { @_SUPPORTED_COMMANDS }

=head2 supported_commands_regexp

Returns a regular expression matching the supported commands of this
implementation.

=cut

my $_SUPPORTED_COMMANDS_REGEXP;
{
    my $alternatives = join '|', @_SUPPORTED_COMMANDS;
    $_SUPPORTED_COMMANDS_REGEXP = qr/^(?:$alternatives)$/;
}

sub supported_commands_regexp { $_SUPPORTED_COMMANDS_REGEXP }

my %_SUPPORTED_COMMANDS_CLASSES = map { lc($_) => 'SyncML::Message::Command::' . ucfirst(lc($_)) } 
                                      @_SUPPORTED_COMMANDS;

=head2 class_for_command $command_name

Returns the name of the L<SyncML::Message::Command> subclass for commands
named C<$command_name>.  (The case of C<$command_name> is irrelevant.)

Example:

    my $class = SyncML::Message::Command->class_for_command('Alert');
    my $alert = $class->new;

=cut

sub class_for_command {
    my $class = shift;
    my $command_name = shift;

    return $_SUPPORTED_COMMANDS_CLASSES{lc($command_name)}; # this is undef if it's unknown
} 


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
  
SyncML::Message::Command requires no configuration files or environment variables.


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
C<bug-syncml-message-command@rt.cpan.org>, or through the web interface at
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

package SyncML::Message::Command::Imperative;
# base class for all commands except Status and Results
use base qw/SyncML::Message::Command/;

sub _build_xml_body {
    my $self = shift;
    my $x = shift;
    
    $x->Target(
        sub {
            $x->LocURI( $self->target_uri );
        }
    ) if defined $self->target_uri;

    $x->Source(
        sub {
            $x->LocURI( $self->source_uri );
        }
    ) if defined $self->source_uri;
}

sub _from_twig {
    my $self = shift;
    my $twig = shift;
    $self->SUPER::_from_twig($twig);

    my $target = $twig->get_nested_child_text('Target', 'LocURI');
    $self->target_uri($target) if defined $target;
    my $source = $twig->get_nested_child_text('Source', 'LocURI');
    $self->source_uri($source) if defined $source;

} 

package SyncML::Message::Command::Alert;
use base qw/SyncML::Message::Command::Imperative/;
__PACKAGE__->mk_accessors(qw/alert_code source_db_uri target_db_uri last_anchor next_anchor/);
# If we support Alerts with multiple databases, this will need to change.

sub command_name { "Alert" }

sub _build_xml_body {
    my $self = shift;
    my $x = shift;
    $self->SUPER::_build_xml_body($x);

    $x->Data( $self->alert_code );

    if (defined $self->source_db_uri) {
        $x->Item(sub{
            $x->Target(sub{
                $x->LocURI($self->target_db_uri);
            });
            $x->Source(sub{
                $x->LocURI($self->source_db_uri);
            });
            $x->Meta(sub{
                $x->Anchor(xmlns => 'syncml:metinf', sub{
                    $x->Last($self->last_anchor);
                    $x->Next($self->next_anchor);
                });
            });
        });
    } 
} 

sub _from_twig {
    my $self = shift;
    my $twig = shift;
    $self->SUPER::_from_twig($twig);

    $self->alert_code( $twig->slimmed_field('Data') );

    if (my $item = $twig->first_child('Item')) {
        my $target = $item->get_nested_child_text('Target', 'LocURI');
        $self->target_db_uri($target) if defined $target;
        my $source = $item->get_nested_child_text('Source', 'LocURI');
        $self->source_db_uri($source) if defined $source;
        my $last = $item->get_nested_child_text('Meta', 'Anchor', 'Last');
        $self->last_anchor($last) if defined $last;
        my $next = $item->get_nested_child_text('Meta', 'Anchor', 'Next');
        $self->next_anchor($next) if defined $next;
    } 
} 


package SyncML::Message::Command::Copy;
use base qw/SyncML::Message::Command::Imperative/;

sub command_name { "Copy" }




package SyncML::Message::Command::Exec;
use base qw/SyncML::Message::Command::Imperative/;

sub command_name { "Exec" }




package SyncML::Message::Command::Get;
use base qw/SyncML::Message::Command::Imperative/;

sub command_name { "Get" }

sub _from_twig {
    my $self = shift;
    my $twig = shift;
    $self->SUPER::_from_twig($twig);

    if (my $URL = $twig->get_nested_child_text('Item', 'Target', 'LocURI')) {
        $self->target_uri($URL);
    } 
} 


package SyncML::Message::Command::Map;
use base qw/SyncML::Message::Command::Imperative/;
__PACKAGE__->mk_accessors(qw/mappings/);

sub command_name { "Map" }

# We don't implement _build_xml_body, because the server never sends
# a Map to the client

sub _from_twig {
    my $self = shift;
    my $twig = shift;
    $self->SUPER::_from_twig($twig);

    my @mappings;
    for my $mapitem ($twig->children('MapItem')) {
        push @mappings, {
            client_identifier      => $mapitem->get_nested_child_text('Source', 'LocURI'),
            application_identifier => $mapitem->get_nested_child_text('Target', 'LocURI'),
        }; 
    } 
    $self->mappings(\@mappings);
} 



package SyncML::Message::Command::Put;
use base qw/SyncML::Message::Command::Imperative/;
sub command_name { "Put" }

sub _from_twig {
    my $self = shift;
    my $twig = shift;
    $self->SUPER::_from_twig($twig);

    if (my $URL = $twig->get_nested_child_text('Item', 'Source', 'LocURI')) {
        $self->source_uri($URL);
    } 
} 

package SyncML::Message::Command::Search;
use base qw/SyncML::Message::Command::Imperative/;

sub command_name { "Search" }




package SyncML::Message::Command::Sync;
use base qw/SyncML::Message::Command::Imperative/;
__PACKAGE__->mk_accessors(qw/subcommands/);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    $self->subcommands([]);
    return $self;
} 

sub command_name { "Sync" }

sub _build_xml_body {
    my $self = shift;
    my $x = shift;
    $self->SUPER::_build_xml_body($x);

    for my $subcommand ( @{ $self->subcommands } ) {
        $x->_x( $subcommand->as_xml );
    }
} 

sub _from_twig {
    my $self = shift;
    my $twig = shift;
    $self->SUPER::_from_twig($twig);

    for my $kid ( $twig->children(SyncML::Message::Command->supported_commands_regexp) )
    {
        my $class = SyncML::Message::Command->class_for_command($kid->tag);
        my $command_obj = $class->new;
        $command_obj->_from_twig($kid);
        push @{ $self->subcommands }, $command_obj;
    }
}

sub sent_all_status {
    my $self = shift;
    return unless $self->SUPER::sent_all_status;

    for my $subcommand ( @{ $self->subcommands } ) {
        return unless $subcommand->sent_all_status;
    }

    return 1;
}

package SyncML::Message::Command::Add;
use base qw/SyncML::Message::Command::Imperative/;
__PACKAGE__->mk_accessors(qw/syncdb_entry/);
sub command_name { "Add" }

sub _build_xml_body {
    my $self = shift;
    my $x = shift;
    $self->SUPER::_build_xml_body($x);

    $x->Meta(sub{
        $x->Type(xmlns => 'syncml:metinf', $self->syncdb_entry->type);
    });
    $x->Item(sub{
        $x->Data($self->syncdb_entry->content); # XXX deal with CDATA?
        $x->Source(sub{
            $x->LocURI($self->syncdb_entry->application_identifier);
        });
    });
}


package SyncML::Message::Command::Replace;
use base qw/SyncML::Message::Command::Imperative/;
__PACKAGE__->mk_accessors(qw/syncdb_entry/);
sub command_name { "Replace" }

sub _build_xml_body {
    my $self = shift;
    my $x = shift;
    $self->SUPER::_build_xml_body($x);

    $x->Meta(sub{
        $x->Type(xmlns => 'syncml:metinf', $self->syncdb_entry->type);
    });
    $x->Item(sub{
        $x->Data($self->syncdb_entry->content); # XXX deal with CDATA?
        $x->Target(sub{
            $x->LocURI($self->syncdb_entry->client_identifier);
        });
    });
}

sub _from_twig {
    my $self = shift;
    my $twig = shift;
    $self->SUPER::_from_twig($twig);

    my $syncdb_entry = SyncML::SyncDBEntry->new;
    # It's possibly that we should check also in Item/Meta/Type
    $syncdb_entry->type             ($twig->get_nested_child_text(qw/Meta Type/));
    $syncdb_entry->content          ($twig->get_nested_child_text(qw/Item Data/));
    $syncdb_entry->client_identifier($twig->get_nested_child_text(qw/Item Source LocURI/));

    $self->syncdb_entry($syncdb_entry);
}


package SyncML::Message::Command::Delete;
use base qw/SyncML::Message::Command::Imperative/;
__PACKAGE__->mk_accessors(qw/client_identifier/);

sub command_name { "Delete" }

sub _build_xml_body {
    my $self = shift;
    my $x = shift;
    $self->SUPER::_build_xml_body($x);

    $x->Item(sub{
        $x->Target(sub{
            $x->LocURI($self->client_identifier);
        });
    });
}

package SyncML::Message::Command::Response;
# base class for Status and Results
use base qw/SyncML::Message::Command/;
__PACKAGE__->mk_accessors(qw/message_reference 
                             command_reference 
                        /);
sub _build_xml_body {
    my $self = shift;
    my $x = shift;

    $x->MsgRef( $self->message_reference );
    $x->CmdRef( $self->command_reference );
}

sub _from_twig {
    my $self = shift;
    my $twig = shift;
    $self->SUPER::_from_twig($twig);

    $self->message_reference     ( $twig->slimmed_field('MsgRef') );
    $self->command_reference     ( $twig->slimmed_field('CmdRef') );

    return;
} 

sub sent_all_status {
    # These commands don't require a status.
    return 1;
} 

package SyncML::Message::Command::Results;
use base qw/SyncML::Message::Command::Response/;
# Assumption: We don't ever care about client->server Results, and the only
# Results we ever send to the client is device info.

sub command_name { "Results" }

sub _build_xml_body {
    my $self = shift;
    my $x = shift;
    $self->SUPER::_build_xml_body($x);
    
    $x->Meta(sub{
        $x->Type(xmlns => 'syncml:metinf', 'application/vnd.syncml-devinf+xml');
    });

    $x->Item(sub {
        $x->Source(sub {
            $x->LocURI('./devinf11');
        });
        $x->Data(sub {
            $x->DevInf(xmlns => 'syncml:devinf', sub {
                $x->VerDTD("1.1");
                $x->Man('bps');
                $x->Mod('SyncML::Engine');
                $x->SwV('0.1');
                $x->HwV('perl');
                $x->DevID('xyzzy');
                $x->DevTyp('server');

                $x->DataStore(
                    sub {
                        $x->SourceRef('./tasks');
                        $x->DisplayName('Tasks');
                        $x->_elt(
                            'Rx-Pref',
                            sub {
                                $x->CTType('text/calendar');
                                $x->VerCT('2.0');
                            }
                        );
                        $x->Rx(sub {
                                $x->CTType('text/x-vcalendar');
                                $x->VerCT('1.0');
                            }
                        );
                        $x->_elt(
                            'Tx-Pref',
                            sub {
                                $x->CTType('text/calendar');
                                $x->VerCT('2.0');
                            }
                        );
                        $x->Tx(sub {
                                $x->CTType('text/x-vcalendar');
                                $x->VerCT('1.0');
                            }
                        );
                        $x->SyncCap(
                            sub {
                                $x->SyncType('1');
                                $x->SyncType('2');
                            }
                        );
                    }
                );
            });
        });
    });
} 


package SyncML::Message::Command::Status;
use base qw/SyncML::Message::Command::Response/;

__PACKAGE__->mk_accessors(qw/status_code 
                             next_anchor_acknowledgement
                        command_name_reference 
                              target_reference 
                              source_reference 
                            include_basic_challenge
                        /);
# next_anchor_acknowledgement is, in the case of a Status responding to an
# Alert, just a duplicate of the Next that the other side sent

sub command_name { "Status" }

sub _build_xml_body {
    my $self = shift;
    my $x = shift;
    $self->SUPER::_build_xml_body($x);

    $x->Data( $self->status_code );

    $x->Cmd( $self->command_name_reference );
    $x->TargetRef( $self->target_reference )
        if defined( $self->target_reference );
    $x->SourceRef( $self->source_reference )
        if defined( $self->source_reference );

    $x->Item(sub{
        $x->Data(sub{
            $x->Anchor( xmlns => 'syncml:metinf', sub{
                $x->Next($self->next_anchor_acknowledgement);
            });
        });
    }) if defined $self->next_anchor_acknowledgement;

    $x->Chal(sub{
        $x->Meta(sub{
            $x->Format(xmlns => 'syncml:metinf', 'b64');
            $x->Type(xmlns => 'syncml:metinf', 'syncml:auth-basic');
        });
    }) if $self->include_basic_challenge;
}

sub _from_twig {
    my $self = shift;
    my $twig = shift;
    $self->SUPER::_from_twig($twig);

    $self->status_code( $twig->slimmed_field('Data') );

    if (my $next = $twig->get_nested_child_text('Item', 'Data', 'Anchor', 'Next')) {
        $self->next_anchor_acknowledgement($next);
    } 
    $self->command_name_reference( $twig->slimmed_field('Cmd') );
    $self->target_reference      ( $twig->slimmed_field('TargetRef') );
    $self->source_reference      ( $twig->slimmed_field('SourceRef') );
} 


package XML::Twig::Elt;

# convenience routine: equivalent to nested ->first_child calls, but doesn't
# bomb out when one returns undef
sub get_nested_child_text {
    my $self = shift;

    my $current = $self;

    while (@_) {
        my $next_tag = shift;
        $current = $current->first_child($next_tag);
        return unless $current;
    } 
    return $current->slimmed_text;
} 

 # version of trimmed_text that doesn't trim interior whitespace
  sub slimmed_text
    { my $elt= shift;
      my $text= $elt->text;
#      $text=~ s{\s+}{ }sg;
      $text=~ s{^\s*}{};
      $text=~ s{\s*$}{};
      return $text;
    }

sub slimmed_field  
  { my $elt= shift;
    my $dest=$elt->first_child(@_) or return '';
    return $dest->slimmed_text;
  }
    
1;
