#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../cpanp";
use CPANPLUS::Backend;

$ENV{PATH} = $ENV{PATH} . ":$FindBin::Bin";

print "pulling down indexes from CPAN, this can take a while\n";

my $cb = CPANPLUS::Backend->new;
$cb->flush('all');
my $conf = $cb->configure_object;

$conf->set_conf(prereqs => 1);
$conf->set_conf(verbose => 1);
$conf->set_conf(signature => 0);
$conf->set_conf(force => 0);
$conf->set_conf(skiptest => 1);
$conf->set_conf(allow_build_interactivity => 0);

my @modules = qw/
  ExtUtils::Depends
  IO::String
  YAML
  Class::Inspector
  Class::MOP
  Moose 
  MooseX::ClassAttribute
  MooseX::Declare
  POE
  POE::Component::IRC
  POE::Component::Server::HTTP
  POE::Component::SSLify
  MooseX::POE
  JSON
  Template
  Template::Plugin::JavaScript
  IRC::Formatting::HTML
  DateTime
  File::ShareDir
  Digest::CRC
/;

for my $module (@modules) {
  my $rv = $cb->install(modules => [$module]);
}
