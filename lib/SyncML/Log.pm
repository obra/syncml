package SyncML::Log;

use warnings;
use strict;

use Log::Log4perl;

=head1 NAME

SyncML::Log - Mixin to provide a Log4perl logger to each class

=head1 SYNPOSIS

   SyncML::Log->log_init('foo.logconf');

   package SyncML::Something;
   use base qw/SyncML::Log/;

   sub method {
     $self->log->info("Something interesting happened.");
   }

=head1 METHODS

=cut

=head2 log_init $file

(Class method.)  Starts the L<Log::Log4perl> logger with the given
configuration file.

=cut 

sub log_init {
  my $class = shift;
  my $file = shift;
  Log::Log4perl->init_and_watch($file);
}

=head2 log_init_default

(Class method.) Starts the L<Log::Log4perl> logger with some default values
(display INFO and above to the screen).

=cut

sub log_init_default {
    my $class = shift;
    my %default = (
        'log4perl.rootLogger'        => "ALL,Screen",
        'log4perl.appender.Screen'   => 'Log::Log4perl::Appender::Screen',
        'log4perl.appender.Screen.stderr' => 1,
        'log4perl.appender.Screen.layout' =>
            'Log::Log4perl::Layout::SimpleLayout'
    );
    Log::Log4perl->init( \%default );
}


=head2 log 

(Mixed in.)  Returns an appropriate logger object for the current
class.

=cut

sub log {
    my $self = shift;
    return Log::Log4perl->get_logger(ref $self);
} 

1;
