package SyncML::Message::Item;

use warnings;
use strict;

use base qw/Class::Accessor/;

use Carp;

=head1 NAME

SyncML::Message::Item - Represents an Item in a SyncML command


=head1 SYNOPSIS

    use SyncML::Message::Item;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.
  
  
=head1 DESCRIPTION

THIS FILE IS PROBABLY ABANDONED, BUT DO READ THE DOCS BELOW!


The C<< <Item> >> SyncML element takes on an annnoying number of roles:

=over 4

=item The target location of a C<Get> (perhaps source too?)

=item The Data, Meta Type, target, and source of a C<Put>

=item The Data and source in a C<Results>

=item The target location of a C<Delete>... or the source

=item A holder for the NextNonce in a C<Status> with a challenge

=item A holder for the repeated Next anchor in a C<Status> to an C<Alert>

=item A holder for the source, Meta Type, and Data for a client-to-server C<Add> or C<Replace>
      (maybe target too).  But the Meta Type can live outside the Item, too.

=item In a synchronization C<Alert>, contains target and source database locators and a Meta
      Anchor section with Last and Next.

=item The source and target of a C<Copy>

=item The target and data of an C<Exec>

=back

Inexplicably, despite the massive overloading of C<< <Item> >>, the items in a C<Map> (which
have a target and source) are represented by C<< <MapItem> >>; this class also represents them also,
with C<is_map_item> set to a true value.


=head1 METHODS

=cut


__PACKAGE__->mk_accessors(
    qw/command_name command_id no_response items subcommands
        target_uri source_uri
        message_reference command_reference
        command_name_reference target_reference source_reference status_code alert_code
        meta_hash
        include_device_info response_status/
);

=head2 new

Creates a new L<SyncML::Message::Item>.

=cut

sub new {
    my $class = shift;
    my $self  = bless {}, $class;


    return $self;
}

=head2 as_xml

Returns the command as an XML string.

=cut

sub as_xml {
    my $self = shift;

    my $x = XML::Builder->new;

    $x->_elt(
        $self->command_name,
        sub {
            $x->CmdID( $self->command_id );

            if ( $self->meta_hash and %{ $self->meta_hash } ) {
                my %mh = %{ $self->meta_hash };
                $x->Meta(
                    sub {
                        if (   defined $mh{'AnchorNext'}
                            or defined $mh{'AnchorLast'} )
                        {
                            $x->Anchor(
                                xmlns => 'syncml:metinf',
                                sub {
                                    $x->Next( $mh{'AnchorNext'} )
                                        if defined $mh{'AnchorNext'};
                                    $x->Last( $mh{'AnchorLast'} )
                                        if defined $mh{'AnchorLast'};
                                }
                            );
                        }
                        while ( my ( $k, $v ) = each %mh ) {
                            next if $k =~ /^Anchor/;

                   # Yes, this is 'xmlns', not 'xml:ns'.  SyncML is weird like
                   # that.
                            $x->_elt( $k, xmlns => 'syncml:metinf', $v );
                        }
                    }
                );
            }

            if (   $self->command_name eq 'Status'
                or $self->command_name eq 'Results' )
            {
                $x->MsgRef( $self->message_reference );
                $x->CmdRef( $self->command_reference );
                $x->Cmd( $self->command_name_reference )
                    if $self->command_name eq 'Status';
                $x->TargetRef( $self->target_reference )
                    if defined_and_length( $self->target_reference );
                $x->SourceRef( $self->source_reference )
                    if defined_and_length( $self->source_reference );

                if ( $self->command_name eq 'Status' ) {
                    $x->Data( $self->status_code );
                } else {    # Results
                    $x->Item(
                        sub {
                            $x->Source(
                                sub {
                                    $x->LocURI( $self->source_uri );
                                }
                                )
                                if defined_and_length $self->source_uri;
                            $x->Data(
                                sub {
                                    $x->_x( $self->_devinfo );
                                }
                                )
                                if $self->include_device_info;
                        }
                    );
                }
            } else {    # not Status or Results: a real command
                $x->NoResp if $self->no_response;
                $x->Data( $self->alert_code )
                    if $self->command_name eq 'Alert';
                if (   $self->command_name eq 'Map'
                    or $self->command_name eq 'Sync' )
                {
                    $x->Target(
                        sub {
                            $x->LocURI( $self->target_uri );
                        }
                    );
                    $x->Source(
                        sub {
                            $x->LocURI( $self->source_uri );
                        }
                    );
                }
            }

            for my $subcommand ( @{ $self->subcommands } ) {
                $x->_x( $subcommand->as_xml );
            }

            my $is_map = $self->command_name eq 'Map';

            # Handle Items / MapItems
            for my $item ( @{ $self->items } ) {
                my $tagname = $is_map ? 'MapItem' : 'Item';
                $x->$tagname(
                    sub {
                        $x->Target(
                            sub {
                                $x->LocURI( $item->{'target_uri'} );
                            }
                            )
                            if defined $item->{'target_uri'};
                        $x->Source(
                            sub {
                                $x->LocURI( $item->{'source_uri'} );
                            }
                            )
                            if defined $item->{'source_uri'};

                        unless ($is_map) {
                            $x->Data( $item->{'data'} )
                                if defined $item->{'data'};

                            if ( $item->{'meta'} and %{ $item->{'meta'} } ) {
                                my %mh = %{ $item->{'meta'} };

                             # bad hack: status probably gets to have Meta too
                                my $tagname = $self->command_name eq 'Status'
                                    ? 'Data'
                                    : 'Meta';
                                $x->$tagname(
                                    sub {
                                        if (   defined $mh{'AnchorNext'}
                                            or defined $mh{'AnchorLast'} )
                                        {
                                            $x->Anchor(
                                                xmlns => 'syncml:metinf',
                                                sub {
                                                    $x->Next(
                                                        $mh{'AnchorNext'} )
                                                        if defined $mh{
                                                        'AnchorNext'};
                                                    $x->Last(
                                                        $mh{'AnchorLast'} )
                                                        if defined $mh{
                                                        'AnchorLast'};
                                                }
                                            );
                                        }
                                        while ( my ( $k, $v ) = each %mh ) {
                                            next if $k =~ /^Anchor/;

                   # Yes, this is 'xmlns', not 'xml:ns'.  SyncML is weird like
                   # that.
                                            $x->_elt(
                                                $k,
                                                xmlns => 'syncml:metinf',
                                                $v
                                            );
                                        }
                                    }
                                );
                            }
                        }
                    }
                );
            }
        }
    );

    return $x->_output;
}

=head2 new_from_xml $string

Creates a new L<SyncML::Message> from the XML document C<$string>.

=cut

sub new_from_xml {
    my $class = shift;
    my $text  = shift;

    my $twig = XML::Twig->new;
    $twig->parse($text);

    return $class->_new_from_twig( $twig->root );
}

sub _new_from_twig {
    my $class   = shift;
    my $command = shift;

    my $self = bless {}, $class;

    $self->items(       [] );
    $self->subcommands( [] );

    $self->command_name( $command->tag );
    $self->command_id( $command->first_child_text('CmdID') );

    if ( $self->command_name eq 'Status' ) {
        $self->message_reference( $command->first_child_text('MsgRef') );
        $self->command_reference( $command->first_child_text('CmdRef') );
        $self->command_name_reference( $command->first_child_text('Cmd') );
        $self->target_reference( $command->first_child_text('TargetRef') );
        $self->source_reference( $command->first_child_text('SourceRef') );
        $self->status_code( $command->first_child_text('Data') );
    } else {
        $self->no_response( $command->has_child('NoResp') ? 1 : 0 );
        $self->alert_code( $command->first_child_text('Data') )
            if $self->command_name eq 'Alert';

        if ( $self->command_name eq 'Map' or $self->command_name eq 'Sync' ) {
            my $target = $command->first_child('Target');
            $self->target_uri(
                $target ? $target->first_child_text('LocURI') : '' );
            my $source = $command->first_child('Source');
            $self->source_uri(
                $source ? $source->first_child_text('LocURI') : '' );
        }

        # Could possibly support more nested things
        for my $kid ( $command->children(qr/^(?:Add|Copy|Delete|Replace)$/) )
        {
            my $command_obj = SyncML::Message::Command->_new_from_twig($kid);
            push @{ $self->subcommands }, $command_obj;
        }

        for my $item (
            $command->children(
                $self->command_name eq 'Map' ? 'MapItem' : 'Item'
            )
            )
        {
            my $item_struct = {};
            my $target      = $item->first_child('Target');
            $item_struct->{'target_uri'} = $target->first_child_text('LocURI')
                if $target;
            my $source = $item->first_child('Source');
            $item_struct->{'source_uri'} = $source->first_child_text('LocURI')
                if $source;
            $item_struct->{'data'} = $item->first_child_text('Data');

            my $meta_hash = {};
            my $meta      = $item->first_child('Meta');
            if ($meta) {
                for my $kid ( $meta->children ) {
                    next
                        if $kid->tag eq
                        'Mem';    # don't feel like dealing with its nesting

                    if ( $kid->tag eq 'Anchor' ) {
                        $meta_hash->{'AnchorLast'}
                            = $kid->first_child_text('Last');
                        $meta_hash->{'AnchorNext'}
                            = $kid->first_child_text('Next');
                    } else {
                        $meta_hash->{ $kid->tag } = $kid->text;
                    }
                }
            }
            $item_struct->{'meta'} = $meta_hash;

            push @{ $self->items }, $item_struct;
        }
    }

    return $self;
}

sub _devinfo {
    my $self = shift;

    my $x = XML::Builder->new;

    $x->DevInf(
        xmlns => "syncml:devinf",
        sub {
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
                    $x->_elt(
                        'Tx-Pref',
                        sub {
                            $x->CTType('text/calendar');
                            $x->VerCT('2.0');
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
        }
    );

    return $x->_output;
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
