#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use App::Alice::MessageBuffer;
use Benchmark qw/:all/;
use AnyEvent;

my $id = time;
my @data = (
    event => "say",
    nick => $ENV{USER},
    html => join "\n", map {$_ => "$_" x 300} (0 .. 10)
);

my %stores = map {$_ => App::Alice::MessageBuffer->new(id => $id, store_class => $_)} qw/Memory TokyoCabinet Cache/;
my $cv = AE::cv;
my $t = AE::timer 1, 0, sub {
  print STDERR "timing\n";
  cmpthese(
    5000, {
      map {
        my $store = $stores{$_};
        $_ => sub {
          $store->add({@data}) for 0 .. 10;
        }
      } keys %stores
    }
  );
  $cv->send;
};
$cv->wait;
