#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/extlib/lib/perl5";
use local::lib "$FindBin::Bin/extlib";
use YAML qw/LoadFile/;
use Alice::HTTPD;
use Alice::IRC;
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

print STDERR "You can view your IRC session at: http://localhost:".$config->{port}."/view\n";

my $httpd = Alice::HTTPD->new(config => $config);
my $irc = Alice::IRC->new(config => $config, httpd => $httpd);

$SIG{INT} = sub {
  my @connections = grep {$_->connected} $irc->connections;
  if (! @connections) {
    print STDERR "Bye!\n";
    exit(0);
  }
  print STDERR "closing connections, ^C again to quit\n";
  for ($irc->connections) {
    $_->call(quit => "alice.");
  }
};

POE::Kernel->run;
