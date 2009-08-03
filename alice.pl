#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use lib 'extlib/lib/perl5';
use local::lib 'extlib';
use YAML qw/LoadFile/;
use Alice::HTTPD;
use Alice::IRC;
use Sys::Hostname;
use POE;

$0 = 'Alice';

my $config = {
  port  => 8080,
  debug => 1,
  style => 'default',
};
if (-e $ENV{HOME}.'/.alice.yaml') {
  eval { $config = LoadFile($ENV{HOME}.'/.alice.yaml') };
}
  
BEGIN { $SIG{__WARN__} = sub { warn $_[0] if $config->{debug} } };

print STDERR "You can view your IRC session at: http://".hostname.":".$config->{port}."/view\n";

my $httpd = Alice::HTTPD->new(config => $config);
my $irc = Alice::IRC->new(config => $config, httpd => $httpd);

POE::Kernel->run;
