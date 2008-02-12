package SyncML::SimpleServer;

use warnings;
use strict;

use base
    qw/SyncML::Log HTTP::Server::Simple::Recorder HTTP::Server::Simple::CGI Class::Accessor/;

use Carp;

use HTTP::Response;
use SyncML::Message;
use SyncML::Engine;
use Sys::HostIP;
use XML::WBXML;

=head1 NAME

SyncML::SimpleServer - an HTTP::Server::Simple to do SyncML


=head1 SYNOPSIS


=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.
  
  
=head1 DESCRIPTION


=head1 METHODS

=head2 handle_request

Handles a single request.

=cut

sub handle_request {
    my $self = shift;
    my $cgi  = shift;

    my $resp = HTTP::Response->new(200);
    $resp->protocol("HTTP/1.1");

    my $using_wbxml = $cgi->content_type eq 'application/vnd.syncml+wbxml';

    my $input = $cgi->param('POSTDATA');
    if ($using_wbxml) {
        $input = XML::WBXML::wbxml_to_xml($input);
    }

    my $in_message = SyncML::Message->new;
    $in_message->from_xml($input);

    return unless $in_message;    # should do some sort of output I guess

    my $engine;

   # Yeah, yeah, parsing our own query strings is usually the sign of an awful
   # CGI, except that CGI.pm is mean and won't parse the query string if
   # there's posted data.
    if ( $ENV{'QUERY_STRING'} =~ /^sid=([0-9a-f]+)/ ) {
        $self->log->info("looking for engine for $1");
        $engine = $self->engine_cache->get($1);
        # XXX Arguably, this should temporarily erase the engine from the cache
        # so that no other request tries to use it too?
        $self->log->warn("couldn't find engine for $1") unless $engine;

    }

    unless ($engine) {
        $engine = SyncML::Engine->new($self->api);
        $engine->uri_base( "http://" . Sys::HostIP->ip . ":8080/" );
    }

    my $out_message = $engine->respond_to_message($in_message);

    if ($engine->done) {
        $self->engine_cache->remove( $engine->internal_session_id );
    } else {
        $self->engine_cache->set( $engine->internal_session_id, $engine);
    }

    my $output = $out_message->as_xml;
    if ($using_wbxml) {    # warn $output;
        $output = XML::WBXML::xml_to_wbxml($output);
    }

    $resp->content($output);
    $resp->content_length( length $resp->content );
    $resp->content_type(
        'application/vnd.syncml+' . ( $using_wbxml ? 'wb' : '' ) . 'xml' );

    print $resp->as_string;
}

=head2 engine_cache

Returns a L<Cache::Cache> containing L<SyncML::Engine> objects, with
C<internal_session_id> as keys.

=cut

sub engine_cache {
    my $self = shift;
    use Cache::FileCache; # could switch this to any other Cache::Cache
    return $self->{'_cache'} ||= 
        Cache::FileCache->new( { namespace => "SyncML-Cache" });
}

=head2 print_banner

Overrides the HSS method to print out a banner including the current IP 
address (as calculated by L<Sys::HostIP>.

=cut

sub print_banner {
    my $self = shift;
    $self->log->info("You can connect to your server at http://",
        Sys::HostIP->ip, ":8080/");
}

=head2 handler

Handler implemented as part of HTTP::Server::Simple API; overrides CGI's
to log better.

=cut

sub handler {
    my $self = shift;
    my $cgi  = new CGI();
    eval { $self->handle_request($cgi) };
    if ($@) {
        my $error = $@;
        $self->log->error($error);
    }
}

1;

__PACKAGE__->mk_accessors(qw/api/);

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
