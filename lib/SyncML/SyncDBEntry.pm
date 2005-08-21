package SyncML::SyncDBEntry;

use warnings;
use strict;

use base qw/Class::Accessor SyncML::ContentAsObject/;

use Carp;
use DateTime;
use Data::ICal;

=head1 NAME

SyncML::SyncDBEntry - Representation of client's copy of a syncable item


=head1 SYNOPSIS

    use SyncML::SyncDBEntry;

  
  
=head1 DESCRIPTION

A L<SyncML::SyncDBEntry> represents the information which is stored about what
a client knows about a single synchronizable item, such as a to-do list
task or an event.  The server keeps a database which can be represented as 
L<SyncML::SyncDBEntry> objects.  Each object contains an object identifying
the client (IMEI/URL, username, database name); the client's local identifier
for the item; the application's identifier for the item; and the content and type of
the item at the last time it was successfully synchronized with the client.

The server uses the sync db to figure out what has changed on the server since the
last synchronization, and in the case of the slow sync, it can help figure out
what has changed on the client.

=head1 METHODS

=head2 new

Creates a new L<SyncML::SyncDBEntry>.

=cut

sub new {
    my $class = shift;
    my $self  = bless {}, $class;

    return $self;
}

=head2 content [$content]

Gets or sets the content of the item.  This should be a string in a format indicated
by the C<type> method.

=head2 type [$type]

Gets or sets the MIME type of the object as a string; for example, C<text/calendar>.

=head2 application_identifier [$application_identifier]

Gets or sets the identifier that the application uses to refer to the item; this is treated
as an opaque string.  Generally this will be the primary key that the application uses to
store the item in a database.

=head2 client_identifier [$client_identifier]

Gets or sets the identifier that the client uses to refer to the item; this is treated
as an opaque string.

=cut

__PACKAGE__->mk_accessors(
    qw/content type application_identifier client_identifier/);

=head2 content_as_object

Returns the object representing C<content> with type C<type>.
See L<SyncML::ContentAsObject> for more information.

=cut

__PACKAGE__->mk_object_accessor( content_as_object => qw/content type/ );

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
