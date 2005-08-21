package SyncML::Message;

our $VERSION = '0.01';

use warnings;
use strict;

use base qw/Class::Accessor/;

use Carp;
use XML::Twig;
use XML::Builder;

use SyncML::Message::Command;

=head1 NAME

SyncML::Message - Represents a SyncML message


=head1 SYNOPSIS

    use SyncML::Message;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.
  
  
=head1 DESCRIPTION

A SyncML message consists of a header and a body.  The body consists of
a series of commands (some of which, such as C<Sync>, can contain other commands).

A L<SyncML::Message> object represents a single message.  It keeps track of the various
information that go in the header, the list of L<SyncML::Command> objects representing
commands, and whether or not this is the final message of a SyncML synchronization package.

(A package is a message or set of messages defined by the SyncML protocol; for example,
the two-way sync protocol consists of 6 packages, 3 in each direction.  There is no object
to represent a package.)

=head1 METHODS

=head2 new

Creates a new L<SyncML::Message>.

=cut

sub new {
    my $class = shift;
    my $self  = bless {}, $class;

    $self->final(1);
    $self->no_response(0);
    $self->commands( [] );
    $self->next_command_id(1);

    return $self;
}

=head2 new_from_xml $string

Creates a new L<SyncML::Message> from the XML document C<$string>.

=cut

sub new_from_xml {
    my $class    = shift;
    my $self     = bless {}, $class;
    my $document = shift;

    my $twig = XML::Twig->new;
    eval { $twig->parse($document); };
    return if $@;

    my $header = $twig->root->first_child('SyncHdr');

    $header->first_child_text('VerDTD') eq '1.1'
        or warn "Document doesn't declare DTD version 1.1!";
    $header->first_child_text('VerProto') eq 'SyncML/1.1'
        or warn "Document doesn't declare specification SyncML/1.1!";

    $self->session_id( $header->first_child_text('SessionID') );
    $self->message_id( $header->first_child_text('MsgID') );

    $self->response_uri( $header->first_child_text('RespURI') );

    {
        my $target = $header->first_child('Target');

        $self->target_uri( $target->first_child_text('LocURI') );
        $self->target_name( $target->first_child_text('LocName') )
            if $target->has_child('LocName');
    }

    {
        my $source = $header->first_child('Source');

        $self->source_uri( $source->first_child_text('LocURI') );
        $self->source_name( $source->first_child_text('LocName') )
            if $source->has_child('LocName');
    }

    $self->no_response( $header->has_child('NoResp') ? 1 : 0 );
    $self->final(
        $twig->root->first_child('SyncBody')->has_child('Final') ? 1 : 0 );

    $self->commands( [] );
    for my $kid (
        $twig->root->first_child('SyncBody')->children(
            qr/^(?:Alert|Copy|Exec|Get|Map|Put|Results|Search|Status|Sync|Add|Replace|Delete)$/
        )
        )
    {
        my $command_obj = SyncML::Message::Command->_new_from_twig($kid);
        push @{ $self->commands }, $command_obj;
    }

    return $self;
}

=head2 as_xml

Returns the SyncML message as an XML document (a C<< <SyncML> >> element; note that
it will not include a doctype declaration or C<< <?xml?> >> declaration, and the
specification does not require it to.)

=cut

sub as_xml {
    my $self = shift;

    my $x = XML::Builder->new;
    $x->SyncML(
        sub {
            $x->SyncHdr(
                sub {
                    $x->VerDTD('1.1');
                    $x->VerProto('SyncML/1.1');
                    $x->SessionID( $self->session_id );
                    $x->MsgID( $self->message_id );
                    $x->RespURI( $self->response_uri ) if $self->response_uri;
                    $x->Target(
                        sub {
                            $x->LocURI( $self->target_uri );
                            $x->LocName( $self->target_name )
                                if defined $self->target_name;
                        }
                    );
                    $x->Source(
                        sub {
                            $x->LocURI( $self->source_uri );
                            $x->LocName( $self->source_name )
                                if defined $self->source_name;
                        }
                    );
                    $x->NoResp if $self->no_response;
                }
            );
            $x->SyncBody(
                sub {
                    for my $command ( @{ $self->commands } ) {
                        $x->_x( $command->as_xml );
                    }
                    $x->Final if $self->final;
                }
            );
        }
    );
    return $x->_output;
}

=head2 stamp_command_id $command

Sets the command_id of C<$command> to C<next_command_id> and increment C<next_command_id>.

=cut

sub stamp_command_id {
    my $self    = shift;
    my $command = shift;
    $command->command_id( $self->next_command_id );
    $self->next_command_id( $self->next_command_id + 1 );
    return;
}

=head2 commands

Returns an array reference to the commands of this message.

=head2 session_id [$session_id]

(Required.) Gets or sets the session ID for this message.  Each synchronization session
has a unique session ID, selected by the originator of the session (generally
the client, as we do not implement Server-Alerted Sync).  It is an arbitrary string.

=head2 message_id [$message_id]

(Required.) Gets or sets the message ID for this message.  Within a session, each message must have
a unique integer ID, starting at 1 and incrementing by one for each message sent.
(Note that each side of the communication has a separate counter; that is, the first
message sent by the client and the first message sent by the server both have message ID
1.)

=head2 target_uri [$target_uri]

(Required.) Gets or sets the URI of the target of this message.  This is not necessarily the URL that
you use to connect to the target over a transport; rather, it's what identifies the target, and
might be an C<IMEI:> URN which identifies a mobile client.  
(This is just identifying the device, not the database or item.)

=head2 target_name [$target_name]

(Optional.) Gets or sets a display name for the target of this message.

=head2 source_uri [$source_uri]

(Required.) Gets or sets the URI of the source of this message.
(This is just identifying the device, not the database or item.)

=head2 source_name [$source_name]

(Optional.) Gets or sets a display name for the source of this message.

=head2 response_uri [$response_uri]

(Required?) Gets or sets the URI that the recipient must use for any response
to this message.

=head2 no_response [$no_response]

Gets or sets a boolean flag (defaults to false) indicating that the recipient must not send
a C<Status> for any of the commands in this message.

=head2 final [$final]

Gets or sets a boolean flag (defaults to true) indicating that this is the final message in
its package.

=head2 credentials

XXX TODO FIXME

=cut

__PACKAGE__->mk_accessors(
    qw/commands session_id message_id target_uri target_name source_uri source_name
        response_uri no_response final next_command_id sent_status_for_header/
);

# Checks to make sure that we've sent a status response to all of the commands
# in the message.
sub sent_all_status {
    my $self = shift;
    return unless $self->sent_status_for_header;

    for my $command ( @{ $self->command } ) {
        return unless $command->sent_all_status;
    }

    return 1;
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
