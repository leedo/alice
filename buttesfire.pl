#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use POE qw/Component::IRC::State Component::Server::HTTP/;
use URI::QueryParam;
use YAML::Any qw/LoadFile/;
use IRC::Formatting;
use Template;
use JSON;
use Encode;
use HTML::Entities;
use Data::Dumper;

my @open_responses;
my $header = "Content-Type: text/plain\r\n\r\n";
my $seperator = "\n--xbuttesfirex\n";

my $config = LoadFile($ENV{HOME}.'/.buttesfire.yaml');
my $tt = Template->new(INCLUDE_PATH => 'data/templates');

my $http = POE::Component::Server::HTTP->new(
  Port             => 8080,
  ContentHandler   => {
    '/view'        => \&send_index,
    '/stream'      => \&setup_stream,
    '/favicon.ico' => \&not_found,
    '/say'         => \&handle_message,
  },
  StreamHandler    => \&handle_stream,
);
my $irc = POE::Component::IRC::State->spawn(
  nick    => $config->{nick}    || 'nick',
  ircname => $config->{ircname} || 'nick',
  server  => $config->{server}  || 'irc.freenode.org',
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
      my $html = '';
      $tt->process('message.tt', {msgs => $res->{msgs}{$channel}}, \$html);
      push @json, {html => decode_utf8($html), channel => $channel};
    }
    $res->{msgs} = {};
    $res->send($header . to_json(\@json)."$seperator$header$seperator") if @json;
    return;
  }
  $res->continue;
}

sub handle_message {
  my ($req, $res) = @_;
  $res->streaming(0);
  if (my $msg = $req->uri->query_param('msg') and 
      my $chan = $req->uri->query_param('chan')) {
    print STDERR "sending message to #$chan\n";
    $irc->yield( privmsg => "#$chan" => $msg);
    display_message($config->{nick}, $chan, $msg);
  }
  $res->code(200);
  return 200;
}

sub send_index {
  my ($req, $res) = @_;
  $res->code(200);
  $res->streaming(0);
  $res->content_type('text/html; charset=utf-8');
  my $output = '';
  $tt->process('index.tt', $config, \$output) or die $!;
  $res->content($output);
  return 200;
}

sub not_found {
  my ($req, $res) = @_;
  $res->streaming(0);
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
  display_message($nick, $channel, $what);
}

sub display_message {
  my ($nick, $channel, $text) = @_;
  my $msg = {
    nick      => $nick,
    channel   => $channel,
    msg       => IRC::Formatting->formatted_string_to_html($text),
    timestamp => sprintf("%02d:%02d", localtime[2,1]),
  };
  print STDERR "adding message to response queues\n" if @open_responses;
  push @{$_->{msgs}{$channel}}, $msg for @open_responses;
}