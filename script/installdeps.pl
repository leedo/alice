#!/usr/bin/perl

use CPANPLUS::Backend;

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
  YAML
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

for (@modules) {
  $cb->install(modules => [$_]);
}

