#!/usr/bin/perl

use strict;
use warnings;

use lib '../lib';
use App::Alice::MessageBuffer;
use Benchmark qw/:all/;
use AnyEvent;

my $id = time;
my $data = sub { 
  {
    event => "say",
    nick => $ENV{USER},
    html => join "\n", map {$_ => "$_" x 1024} (0 .. 300)
  };
};

my $store = App::Alice::MessageBuffer->new(id => $id, store_class => $ARGV[0]);

for (0 .. 1000) {
  $store->add($data->());
}

print STDERR "added 1000 records\n";

AE::cv->wait;
