#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
#use lib 'extlib/lib/perl5';
#use local::lib 'extlib';
use YAML qw/LoadFile DumpFile/;
use Buttes::HTTPD;
use Buttes::IRC;
use POE;

$0 = 'buttesfire-web';
my $config = LoadFile($ENV{HOME}.'/.buttesfire.yaml');
  
BEGIN { $SIG{__WARN__} = sub { warn $_[0] if $config->{debug} } };

log_info("You can view your IRC session at: http://localhost:8080/view");

my $httpd = Buttes::HTTPD->new(config => $config);
my $irc = Buttes::IRC->new(config => $config, httpd => $httpd);
$httpd->ircs($irc->connections);

POE::Kernel->run;

sub log_debug {
  return unless $config->{debug};
  print STDERR join " ", @_, "\n";
}

sub log_info {
  print STDERR join " ", @_, "\n";
}

