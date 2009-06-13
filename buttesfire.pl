#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use POE qw/Component::IRC::State Component::Server::HTTP/;
use YAML::Any qw/LoadFile/;
use IRC::Formatting;
use Template;
use JSON;

my @open_responses;
my $header = "Content-Type: text/plain\r\n\r\n";
my $seperator = "\n--xbuttesfirex\n";

my $config = LoadFile($ENV{HOME}.'/.buttesfire.yaml');
my $tt = Template->new(INCLUDE_PATH => 'data/templates');

my $http = POE::Component::Server::HTTP->new(
  Port           => 8080,
  ContentHandler => {
    '/view'        => \&send_index,
    '/stream'      => \&setup_stream,
    '/favicon.ico' => \&not_found,
  },
  StreamHandler    => \&handle_stream,
);
my $irc = POE::Component::IRC::State->spawn(
  nick    => $config->{nick}    || 'jew888',
  ircname => $config->{ircname} || 'jew888',
  server  => $config->{server}  || 'irc.buttes.org',
  port    => $config->{port}    || 6667,
);

POE::Session->create(
  package_states => [
    main => [qw/_start irc_public irc_001/]
  ],
);

$poe_kernel->run;

sub setup_stream {
  my ($req, $res) = @_;
  $res->streaming(1);
  $res->code(200);
  $res->content_type('multipart/x-mixed-replace; boundary=xbuttesfirex');
  $res->{msgs} = {};
  push @open_responses, $res;
  print STDERR "opening an http connection\n";
  return 200;
}

sub handle_stream {
  my ($req, $res) = @_;
  if ($res->is_error) {
    $res->close;
    print STDERR "closing broken HTTP connection\n";
    return;
  }
  if (exists $res->{msgs} and keys %{$res->{msgs}}) {
    if (! $res->{started}) {
      $res->{started} = 1;
      $res->send($seperator);
    }
    my @json;
    for my $channel (keys %{$res->{msgs}}) {
      my $channel_text = '';
      $tt->process('message.tt', {msgs => $res->{msgs}{$channel}}, \$channel_text);
      push @json, {text => $channel_text, channel => $channel};
    }
    $res->{msgs} = {};
    $res->send($header.to_json(\@json)."$seperator$header$seperator") if @json;
    return;
  }
  $res->continue;
}

sub send_index {
  my ($req, $res) = @_;
  $res->code(200);
  $res->content_type('text/html');
  my $output = '';
  $tt->process('index.tt', $config, \$output) or die $!;
  $res->content($output);
  return 200;
}

sub not_found {
  my ($req, $res) = @_;
  $res->code(404);
  return 404;
}

sub _start {
  $irc->yield( register => 'all' );
  $irc->yield( connect => { } );
  return;
}

sub irc_001 {
  for (@{$config->{channels}}) {
    $irc->yield( join => $_ );
  }
}

sub irc_public {
  my ($who, $where, $what) = @_[ARG0 .. ARG2];
  my $nick = ( split /!/, $who )[0];
  my $channel =$where->[0];
  $channel =~ s/^\#//;
  my $msg = {
    nick      => $nick,
    channel   => $channel,
    msg       => IRC::Formatting->formatted_string_to_html($what),
    timestamp => sprintf("%02d:%02d", localtime[2,1]),
  };
  print STDERR "adding message to HTTP queues\n" if @open_responses;
  push @{$_->{msgs}{$channel}}, $msg for @open_responses;
}