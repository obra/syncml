package SyncML::Message::Command;

use warnings;
use strict;

use base qw/Class::Accessor/;

use Carp;
use XML::Twig;


=head1 NAME

SyncML::Message::Command - Represents a single (possibly compound) SyncML command


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

=head2 command_name [$command_name]

(Required.) Gets or sets the SyncML command name, such as C<Add>, C<Status>, or C<Sync>.

=head2 command_id [$command_id]

(Required.) Gets or sets the command ID for the command, a non-empty, non-C<"0"> text value.

=head2 no_response [$no_response]

Gets or sets a boolean flag (defaults to false) indicating that the recipient must not send
a C<Status> for this command.

=head2 credentials

XXX TODO FIXME

=head2 items

Returns an array reference to the items contained in this command.  (In the case of the C<Map> command,
these are actually C<MapItem>s, not C<Item>s.)  For now these are just hashes of target_uri, source_uri,
data.

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

__PACKAGE__->mk_accessors(qw/command_name command_id no_response items subcommands
                             target_uri source_uri
			     message_reference command_reference 
			     command_name_reference target_reference source_reference status_code alert_code/);

=head2 new [$command_name]

Creates a new L<SyncML::Message::Command>, with command name C<$command_name> if it's given.

=cut

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    $self->command_name(shift) if @_;

    $self->items([]);
    $self->subcommands([]);
    $self->no_response(0);

    return $self;
} 

=head2 as_xml

Returns the command as an XML string.

=cut

sub as_xml {
    my $self = shift;
    $self->_as_twig->sprint;
} 

sub _as_twig {
    my $self = shift;

    my $command = XML::Twig::Elt->new($self->command_name);
    $command->set_pretty_print('indented');

    XML::Twig::Elt->new('CmdID', $self->command_id)->paste(last_child => $command);

    if ($self->command_name eq 'Status') {
	XML::Twig::Elt->new('MsgRef', $self->message_reference)->paste_last_child($command);
	XML::Twig::Elt->new('CmdRef', $self->command_reference)->paste_last_child($command);
	XML::Twig::Elt->new('Cmd', $self->command_name_reference)->paste_last_child($command);

	XML::Twig::Elt->new('TargetRef', $self->target_reference)->paste_last_child($command);
	XML::Twig::Elt->new('SourceRef', $self->source_reference)->paste_last_child($command);
	
	XML::Twig::Elt->new('Data', $self->status_code)->paste_last_child($command);
    } else {
	XML::Twig::Elt->new('NoResp')->paste_last_child($command) if $self->no_response;
	XML::Twig::Elt->new('Data', $self->alert_code)->paste_last_child($command) if $self->command_name eq 'Alert';
	if ($self->command_name eq 'Map' or $self->command_name eq 'Sync') {
	    my $target = XML::Twig::Elt->new('Target');
	    my $source = XML::Twig::Elt->new('Source');
	    $target->paste_last_child($command);
	    $source->paste_last_child($command);

	    XML::Twig::Elt->new('LocURI', $self->target_uri)->paste($target);
	    XML::Twig::Elt->new('LocURI', $self->source_uri)->paste($source);
	} 
    } 

    for my $subcommand (@{ $self->subcommands }) {
	$subcommand->_as_twig->paste_last_child($command);
    } 
    
    my $is_map = $self->command_name eq 'Map';

    for my $item (@{ $self->items }) {
	my $item_twig = XML::Twig::Elt->new($is_map ? 'MapItem' : 'Item');
	if (defined $item->{'target_uri'}) {
	    my $e = XML::Twig::Elt->new('Target');
	    XML::Twig::Elt->new('LocURI', $item->{'target_uri'})->paste($e);
	    $e->paste_last_child($item_twig);
	}
	if (defined $item->{'source_uri'}) {
	    my $e = XML::Twig::Elt->new('Source');
	    XML::Twig::Elt->new('LocURI', $item->{'source_uri'})->paste($e);
	    $e->paste_last_child($item_twig);
	}

	unless ($is_map) {
	    XML::Twig::Elt->new('Data', $item->{'data'})->paste_last_child($item_twig)
		if defined $item->{'data'};
	    if ($item->{'meta'} and %{ $item->{'meta'} }) {
		# bad hack: status probably gets to have meta too
		my $meta = XML::Twig::Elt->new($self->command_name eq 'Status' ? 'Data' : 'Meta');
		my $anchor = XML::Twig::Elt->new('Anchor');
		while (my ($k, $v) = each %{ $item->{'meta'} }) {
		    if ($k =~ s/^Anchor//) {
			XML::Twig::Elt->new($k, $v)->paste_last_child($anchor);
		    } else {
			XML::Twig::Elt->new($k, $v)->paste_last_child($meta);
		    } 
		} 
		$anchor->paste_last_child($meta) if $anchor->has_children;
		for my $metinf ($meta->children) {
		    # Yes, this is 'xmlns', not 'xml:ns'.  SyncML is weird like
		    # that.
		    $metinf->set_att(xmlns => "syncml:metinf");
		} 
		$meta->paste_last_child($item_twig);
	    }
	}

	$item_twig->paste_last_child($command);
    } 

    return $command;
} 

=head2 new_from_xml $string

Creates a new L<SyncML::Message> from the XML document C<$string>.

=cut

sub new_from_xml {
    my $class = shift;
    my $text = shift;
    
    my $twig = XML::Twig->new;
    $twig->parse($text);

    return $class->_new_from_twig($twig->root);
}

sub _new_from_twig {
    my $class = shift;
    my $command = shift;

    my $self = bless {}, $class;

    $self->items([]);
    $self->subcommands([]);

    $self->command_name($command->tag);
    $self->command_id($command->first_child_text('CmdID'));

    if ($self->command_name eq 'Status') {
	$self->message_reference($command->first_child_text('MsgRef'));
	$self->command_reference($command->first_child_text('CmdRef'));
	$self->command_name_reference($command->first_child_text('Cmd'));
	$self->target_reference($command->first_child_text('TargetRef'));
	$self->source_reference($command->first_child_text('SourceRef'));
	$self->status_code($command->first_child_text('Data'));
    } else {
	$self->no_response( $command->has_child('NoResp') ? 1 : 0 );
	$self->alert_code($command->first_child_text('Data')) if $self->command_name eq 'Alert';

	if ($self->command_name eq 'Map' or $self->command_name eq 'Sync') {
	    my $target = $command->first_child('Target');
	    $self->target_uri($target ? $target->first_child_text('LocURI') : '');
	    my $source = $command->first_child('Source');
	    $self->source_uri($source ? $source->first_child_text('LocURI') : '');
	} 
	
	# Could possibly support more nested things
	for my $kid ($command->children(qr/^(?:Add|Copy|Delete|Replace)$/)) {
	    my $command_obj = SyncML::Message::Command->_new_from_twig($kid);
	    push @{ $self->subcommands }, $command_obj;
	} 

	for my $item ($command->children($self->command_name eq 'Map' ? 'MapItem' : 'Item')) {
	    my $item_struct = {};
	    my $target = $item->first_child('Target');
	    $item_struct->{'target_uri'} = $target->first_child_text('LocURI') if $target;
	    my $source = $item->first_child('Source');
	    $item_struct->{'source_uri'} = $source->first_child_text('LocURI') if $source;
	    $item_struct->{'data'} = $item->first_child_text('Data');

	    my $meta_hash = {};
	    my $meta = $item->first_child('Meta');
	    if ($meta) {
		for my $kid ($meta->children) {
		    next if $kid->tag eq 'Mem'; # don't feel like dealing with its nesting

		    if ($kid->tag eq 'Anchor') {
			$meta_hash->{'AnchorLast'} = $kid->first_child_text('Last');
			$meta_hash->{'AnchorNext'} = $kid->first_child_text('Next');
		    } else {
			$meta_hash->{$kid->tag} = $kid->text;
		    } 
		} 
	    } 
	    $item_struct->{'meta'} = $meta_hash;
	    
	    push @{ $self->items }, $item_struct;
	} 
    }

    return $self;
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

1;
