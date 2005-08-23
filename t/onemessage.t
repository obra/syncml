package t::onemessage;
use strict;
use warnings;
use base qw/t::SyncMLServer/;

use Test::WWW::Mechanize;
use Test::More;

sub send_message : Test(21) {
    my $self = shift;
    my $message = SyncML::Message->new;
    isa_ok($message, 'SyncML::Message');

    $message->session_id('1');
    is($message->session_id, 1);
    $message->message_id('1');
    is($message->message_id, 1);

    $message->target_uri( $self->{URL} );
    is($message->target_uri, $self->{URL});
    $message->source_uri( '12345677' );
    is($message->source_uri, '12345677');

    my $response = $self->post_ok($message);
    isa_ok($response, 'SyncML::Message');

    is($response->session_id, '1');
    is($response->message_id, '1');
    is($response->target_uri, '12345677');
    is($response->source_uri, $self->{URL});

    like($response->response_uri, qr{^\Q$self->{URL}\E/\?sid=});

    is(scalar @{ $response->commands }, 1, "got one command back");
    my $status = $response->commands->[0];
    isa_ok($status, 'SyncML::Message::Command');
    is($status->command_name, 'Status');
    is($status->status_code, '407');

    is($status->message_reference, 1);
    is($status->command_reference, 0);
    is($status->command_name_reference, 'SyncHdr');
    is($status->target_reference, $self->{URL} );
    is($status->source_reference, '12345677');
} 

__PACKAGE__->runtests;
