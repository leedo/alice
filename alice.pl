#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/extlib/lib/perl5";
use local::lib "$FindBin::Bin/extlib";
use YAML qw/LoadFile/;
use Alice;

$0 = 'Alice';

my $config = {
  port  => 8080,
  debug => 0,
  style => 'default',
};
if (-e $ENV{HOME}.'/.alice.yaml') {
  eval { $config = LoadFile($ENV{HOME}.'/.alice.yaml') };
}
  
BEGIN { $SIG{__WARN__} = sub { warn $_[0] if $config->{debug} } };

print STDERR "You can view your IRC session at: http://localhost:".$config->{port}."/view\n";

my $alice = Alice->new(config => $config);

$SIG{INT} = sub {
  my @connections = grep {$_->connected} $alice->connections;
  if (! @connections) {
    print STDERR "Bye!\n";
    exit(0);
  }
  print STDERR "closing connections, ^C again to quit\n";
  for ($alice->connections) {
    $_->call(quit => "alice.");
  }
};

$alice->run;
