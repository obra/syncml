package SyncML::ContentAsObject;

use warnings;
use strict;

use Carp;
use DateTime;
use Data::ICal;

use Sub::Installer;

=head1 NAME

SyncML::ContentAsObject - Mixin to provide MIME type-based object serialization


=head1 SYNOPSIS

    package SyncML::FooBar;
    use base qw/SyncML::ContentAsObject Class::Accessor/;

    # this is from Class::Accessor:
    __PACKAGE__->mk_accessors(qw/item_content item_type/); 
    # this is from SyncML::ContentAsObject:
    __PACKAGE__->mk_object_accessor(item_content_as_object => qw/item_content item_type/);

    $foobar->item_content("BEGIN:VCALENDAR...");
    $foobar->item_type("text/calendar");
    my $cal = $foobar->item_content_as_object; # isa Data::ICal

  
  
=head1 DESCRIPTION

L<SyncML::ContentAsObject> is a mixin to create C<foo_as_object> accessors for common
SyncML data types.  Your class must inherit from it and call C<mk_object_accessor> at least once.

Supported types:

    text/calendar, text/x-vcalendar: Data::ICal

=head1 METHODS

=cut

=head2 mk_object_accessor $object_accessor_name, $content_accessor_name, $type_accessor_name

This class method creates an accessor (read-only for now, but this should be
fixed) called C<$object_accessor_name> in the class which converts the content found at
C<$content_accessor_name> with MIME type found at C<$type_accessor_name> into an object 
of the appropriate format.

C<$content_accessor_name> and C<$type_accessor_name> should name standard L<Class::Accessor>-style
accessors.

If the type or content is undefined, or the type is not known, or if the content
is not a valid instance of its type, the constructed accessor returns undef.

=cut

sub mk_object_accessor {
    my $class                 = shift;
    my $object_accessor_name  = shift;
    my $content_accessor_name = shift;
    my $type_accessor_name    = shift;

    $class->install_sub(
        {   $object_accessor_name => sub {
                my $self = shift;
                return $self->__content_as_object( $content_accessor_name,
                    $type_accessor_name, @_ );
                }
        }
    );
}

my %KNOWN_TYPE_CONSTRUCTORS = (
    'text/calendar'    => sub { Data::ICal->new( data => shift ) },
    'text/x-vcalendar' => sub { Data::ICal->new( data => shift ) },
);

sub __content_as_object {
    my $self             = shift;
    my $content_accessor = shift;
    my $type_accessor    = shift;

    my $content = $self->$content_accessor;
    my $type    = $self->$type_accessor;

    return unless defined $content and defined $type;

    return unless $KNOWN_TYPE_CONSTRUCTORS{$type};
    return $KNOWN_TYPE_CONSTRUCTORS{$type}->($content);
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
