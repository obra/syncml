package t::SyncMLServer;
use strict;
use warnings;

use Test::More;
use base qw/t::SyncML/;

sub start_server : Test(startup => 6) {
    my $self = shift;
    use_ok 'Test::HTTP::Server::Simple';
    use_ok 'SyncML::SimpleServer';
    use_ok 'HTTP::Server::Simple::Recorder';

    @Test::SyncML::SimpleServer::ISA = qw/Test::HTTP::Server::Simple SyncML::SimpleServer/;
    
    unshift @Test::SyncML::SimpleServer::ISA, 'HTTP::Server::Simple::Recorder'
	if $ENV{TEST_RECORD};

    $self->{server} = Test::SyncML::SimpleServer->new;
    isa_ok($self->{server}, 'SyncML::SimpleServer');
    isa_ok($self->{server}, 'Test::HTTP::Server::Simple');

    $self->{URL} = $self->{server}->started_ok;

} 

sub post_ok {
    my $self = shift;
    my $message = shift;

    my $mech = Test::WWW::Mechanize->new;

    $mech->post($self->{URL}, Content => $message->as_xml, 'Content-Type' => "application/vnd.syncml+xml");
    ok($mech->success, "request successful");
    return SyncML::Message->new_from_xml($mech->content);
} 

1;
