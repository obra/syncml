#!perl
package t::SyncML;
use strict;
use warnings;

use base qw/Test::Class/;

sub init_log : Test(startup) {
    my $self = shift;

    # For some reason, 'use'ing Log::Log4perl was giving weird "subroutine
    # redefined" warnings
    require Log::Log4perl;
    Log::Log4perl->init_once(\<<'LOG_CONF');
log4perl.rootLogger=DEBUG, LogToFile, ErrorsToFile

log4perl.appender.LogToFile=Log::Log4perl::Appender::File
log4perl.appender.LogToFile.filename=t/test.log
log4perl.appender.LogToFile.mode=append
log4perl.appender.LogToFile.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LogToFile.layout.ConversionPattern=%d %p> %F{1}:%L %M - %m%n

log4perl.appender.ErrorsToFile=Log::Log4perl::Appender::File
log4perl.appender.ErrorsToFile.filename=t/test.error.log
log4perl.appender.ErrorsToFile.mode=append
log4perl.appender.ErrorsToFile.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.ErrorsToFile.layout.ConversionPattern=%d %p> %F{1}:%L %M - %m%n
log4perl.appender.ErrorsToFile.Threshold=WARN
LOG_CONF
} 

1;
