use strict;
use warnings;

use SyncML::Message;

package SyncServer;

use base qw/HTTP::Server::Simple::CGI/;

use HTTP::Response;
use YAML;

sub handle_request {
    my $self = shift;
    my $cgi = shift;

    my $resp = HTTP::Response->new(200);
    $resp->protocol("HTTP/1.1");

    my $message = SyncML::Message->new_from_xml($cgi->param('POSTDATA'));

    warn Dump $message;
    warn $message->as_xml;

    $resp->content($message->as_xml); # bounce it back like an idiot
    $resp->content_length(length $resp->content);
    $resp->content_type('application/vnd.syncml+xml');

    print $resp->as_string;
}

sub handle_header {
    my $action = shift;
    my $in_msgid = shift;

    my $status = XML::Twig::Elt->new('Status');

    XML::Twig::Elt->new('MsgRef', $in_msgid)->paste($status);
    XML::Twig::Elt->new('CmdRef', 0)->paste($status);
    XML::Twig::Elt->new('Cmd', $action->tag)->paste($status);

    XML::Twig::Elt->new('Data', '212')->paste($status);

    return $status;
}

sub handle_alert {
    my $action = shift;
    my $in_msgid = shift;

    my $status = XML::Twig::Elt->new('Status');

    XML::Twig::Elt->new('MsgRef', $in_msgid)->paste($status);
    XML::Twig::Elt->new('CmdRef', $action->first_child('CmdID')->text)->paste($status);
    XML::Twig::Elt->new('Cmd', $action->tag)->paste($status);
    XML::Twig::Elt->new('Data', '200')->paste($status);

    my $alert = XML::Twig::Elt->new('Alert');
    XML::Twig::Elt->new('MsgRef', $in_msgid)->paste($alert);
    XML::Twig::Elt->new('Data', '201')->paste($alert);
    my $item = XML::Twig::Elt->new('Item');
    $action->first_child('Item')->first_child('Target')->copy->set_tag('Source')->paste($item);
    $action->first_child('Item')->first_child('Source')->copy->set_tag('Target')->paste($item);
    $item->paste($alert);


    return $status, $alert;
} 

package main;

SyncServer->new->run;

