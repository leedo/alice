#!/usr/bin/perl

use CPANPLUS::Backend;

my $cb = CPANPLUS::Backend->new;
my $conf = $cb->configure_object;

$conf->set_conf(prereqs => 1);
$conf->set_conf(verbose => 1);
$conf->set_conf(signature => 0);
$conf->set_conf(force => 1);
$conf->set_conf(skiptest => 1);
$conf->set_conf(allow_build_interactivity => 0);

$cb->install(modules => [
  qw/POE POE::Component::IRC POE::Component::Server::HTTP
  POE::Component::SSLify Moose MooseX::POE
  MooseX::ClassAttribute MooseX::Declare YAML
  JSON Template Template::Plugin::JavaScript
  IRC::Formatting::HTML DateTime File::ShareDir
  Digest::CRC/]);
