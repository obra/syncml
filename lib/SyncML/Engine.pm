package SyncML::Engine;

use warnings;
use strict;

use base qw/Class::Accessor/;

use Carp;
use SyncML::Message;
use SyncML::Message::Command;
use Digest::MD5;


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
    Alert => 'handle_alert',
);

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    
    $self->uri_base("http://localhost:8080/");
    $self->last_message_id(0);

    $self->_generate_internal_session_id;

    return $self;
}

sub respond_to_message {
    my $self = shift;
    my $in_message = shift;

    my $out_message = SyncML::Message->new;

    $self->in_message($in_message);
    $self->out_message($out_message);

    warn "Weird: session ID is different" 
	if defined $self->session_id and $in_message->session_id ne $self->session_id;
    $self->session_id($in_message->session_id);
    $out_message->session_id($in_message->session_id);

    $self->last_message_id($self->last_message_id + 1);
    $out_message->message_id($self->last_message_id);

    $out_message->response_uri($self->uri_base . "?sid=" . $self->internal_session_id);

    $out_message->source_uri($in_message->target_uri);
    $out_message->target_uri($in_message->source_uri);

    $self->add_status_for_header(200);

    for my $command (@{ $in_message->commands }) {
	# The following method call does insert the status object into the
	# output message, but any modifications to it will still be effective
	my $status = $self->add_status_for_command($command);

	if (my $handler = $COMMAND_HANDLERS{ $command->command_name }) {
	    $self->$handler($command, $status);
	} else {
	    $status->status_code(200);
	} 
    } 

    return $out_message;
}

sub add_status_for_header {
    my $self = shift;
    my $status_code = shift;

    my $status = SyncML::Message::Command->new;
    $status->command_name('Status');
    $self->out_message->stamp_command_id($status);

    $status->message_reference($self->in_message->message_id);
    $status->command_reference('0');
    $status->command_name_reference('SyncHdr');

    $status->target_reference($self->in_message->target_uri);
    $status->source_reference($self->in_message->source_uri);

    $status->status_code($status_code);

    push @{ $self->out_message->commands }, $status;
    return;
} 

sub add_status_for_command {
    my $self = shift;
    my $command = shift;

    my $status = SyncML::Message::Command->new;
    $status->command_name('Status');
    $self->out_message->stamp_command_id($status);

    $status->message_reference($self->in_message->message_id);
    $status->command_reference($command->command_id);
    $status->command_name_reference($command->command_name);

    $status->target_reference($command->target_uri) if defined_and_length($command->target_uri);
    $status->source_reference($command->source_uri) if defined_and_length($command->source_uri);

    push @{ $self->out_message->commands }, $status;
    return $status;
} 

sub _generate_internal_session_id {
    my $self = shift;

    $self->internal_session_id( Digest::MD5::md5_hex(rand) );
} 

sub handle_alert {
    my $self = shift;
    my $command = shift;
    my $status = shift;

    $status->status_code(200);

    die unless @{ $command->items } == 1;
    die unless $command->alert_code == 200;

    my $item = $command->items->[0];

    push @{ $status->items }, { meta => { AnchorNext => $item->{'meta'}->{'AnchorNext'} }};

    my $response_alert = SyncML::Message::Command->new;
    $response_alert->command_name('Alert');
    $self->out_message->stamp_command_id($response_alert);
    push @{ $self->out_message->commands }, $response_alert;
    $response_alert->alert_code('201'); # slow sync
    push @{ $response_alert->items }, { 
	meta => { AnchorNext => 5678, AnchorLast => 1234 },
	source_uri => $item->{'target_uri'},
	target_uri => $item->{'source_uri'},
    };
} 


__PACKAGE__->mk_accessors(qw/session_id internal_session_id last_message_id uri_base in_message out_message/);

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
