package t::syncable_item;
use strict;
use warnings;
use base qw/t::SyncML/;

use Test::More;

sub startup : Test(startup => 1) {
    use_ok 'SyncML::SyncableItem';
} 

sub make_fixtures : Test(setup => 1) {
    my $self = shift;
    
    $self->{empty} = SyncML::SyncableItem->new;
    isa_ok($self->{empty}, 'SyncML::SyncableItem');
}

sub basic_accessors : Test(13) {
    my $self = shift;
    my $i = $self->{empty};
    ok((not defined $i->application_identifier), "app id not defined");
    $i->application_identifier(42);
    is($i->application_identifier, 42, "app id set");
    ok((not defined $i->content), "content not defined");
    $i->content("BEGIN:VCALENDAR\nEND:VCALENDAR\n");
    is($i->content, "BEGIN:VCALENDAR\nEND:VCALENDAR\n", "content set");
    ok((not defined $i->type), "type not defined");
    $i->type("text/calendar");
    is($i->type, "text/calendar", "type set");
    
    ok((not defined $i->last_modified), "last modified not defined");
    ok((not defined $i->last_modified_as_seconds), "last modified (as seconds) not defined");
    
    my $dt = DateTime->from_epoch(epoch => int(rand(2_000_000_000)));
    isa_ok($dt, 'DateTime');
    $i->last_modified($dt);
    isa_ok($i->last_modified, 'DateTime');
    is("@{[$i->last_modified]}", "$dt", "last mod looks like what we put in");
    is($i->last_modified->epoch, $dt->epoch, "last mod epoch is what we put in");
    is($i->last_modified_as_seconds, $dt->epoch, "last mod seconds is what we put in");
}

sub set_last_mod_as_seconds : Test(4) {
    my $i = shift->{empty};

    ok((not defined $i->last_modified), "last modified not defined");
    ok((not defined $i->last_modified_as_seconds), "last modified (as seconds) not defined");

    my $dt = DateTime->from_epoch(epoch => int(rand(2_000_000_000)));
    $i->last_modified_as_seconds($dt->epoch);
    is($i->last_modified_as_seconds, $dt->epoch);
    is($i->last_modified->epoch, $dt->epoch);
}

sub content_as_object : Test(8) {
    my $i = shift->{empty};

    ok((not defined $i->content_as_object), "type and content undef");
    $i->content(<<'ENDVCAL');
BEGIN:VCALENDAR
VERSION:2.0
PRODID:SyncML
BEGIN:VTODO
SUMMARY:This is an event.
STATUS:NEEDS-ACTION
END:VTODO
END:VCALENDAR
ENDVCAL
    ok((not defined $i->content_as_object), "type undef");
    $i->type("text/calendaryay");
    ok((not defined $i->content_as_object), "unknown type");
    $i->type("text/calendar"); 
    
    my $ical = $i->content_as_object;
    isa_ok($ical, "Data::ICal");
    isa_ok($ical, "Data::ICal::Entry");

    is(scalar @{ $ical->entries }, 1, "has one entry");
    isa_ok($ical->entries->[0], 'Data::ICal::Entry::Todo');

    is($ical->entries->[0]->property('summary')->[0]->value, "This is an event.");
} 

__PACKAGE__->runtests;
