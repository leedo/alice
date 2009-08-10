package Alice::CommandDispatch;

use Moose;
use Encode;

use strict;
use warnings;

has 'handlers' => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub {
    my $self = shift;
    [
      {method => '_say',     re => qr{^([^/].*)}},
      {method => 'query',    re => qr{^/query\s+(.+)}},
      {method => 'names',    re => qr{^/n(?:ames)?}, in_channel => 1},
      {method => '_join',    re => qr{^/j(?:oin)?\s+(.+)}},
      {method => 'part',     re => qr{^/part(?:\s+(.+))?}},
      {method => 'create',   re => qr{^/window new (.+)}},
      {method => 'close',    re => qr{^/window close (.+)}},
      {method => 'topic',    re => qr{^/topic(?:\s+(.+))?}, in_channel => 1},
      {method => 'me',       re => qr{^/me (.+)}},
      {method => 'quote',    re => qr{^/(?:quote|raw) (.+)}},
      {method => 'notfound', re => qr{^/(.+)(?:\s.*)?}}
    ]
  }
);

has 'http' => (
  is       => 'ro',
  isa      => 'Alice::HTTPD',
  required => 1,
);

sub handle {
  my ($self, $command, $source, $connection) = @_;
  for my $handler (@{$self->handlers}) {
    my $re = $handler->{re};
    if ($command =~ /$re/) {
      my $method = $handler->{method};
      my $arg = $1;
      return if ($handler->{in_channel} and $source !~ /^[#&]/);
      $self->$method($source, $connection, $arg);
      return;
    }
  }
}

sub names {
  my ($self, $source, $connection, $arg) = @_;
  $self->http->show_nicks($source, $connection->session_alias);
}

sub query {
  my ($self, $source, $connection, $arg) = @_;
  $self->http->create_window($arg, $connection->session_alias);
}

sub _join {
  my ($self, $source, $connection, $arg) = @_;
  $connection->yield("join", $arg);
}

sub part {
  my ($self, $source, $connection, $arg) = @_;
  if ($arg and $arg =~ /^[#&]/) {
    $connection->yield("part", $arg);
    delete $self->http->{msgbuffer}{$arg};
  }
  elsif ($arg or $source !~ /^[#&]/) {
    $self->http->display_announcement($source, $connection->session_alias,
      "Can only /part a channel");
  }
  else {
    $connection->yield("part", $source);
    delete $self->http->{msgbuffer}{$source};
  }
}

sub close {
  my ($self, $source, $connection, $arg) = @_;
  if ($arg =~ /^[#&]/) {
    $connection->yield("part", $arg);
  }
  delete $self->http->{msgbuffer}{$arg};
}

sub window {
  my ($self, $source, $connection, $arg) = @_;
  $self->http->create_window($arg, $connection->session_alias);
}

sub topic {
  my ($self, $source, $connection, $arg) = @_;
  if ($arg) {
    $connection->yield("topic", $source, $arg);
  }
  else {
    my $topic = $connection->channel_topic($source);
    $self->http->send_topic(
      $topic->{SetBy}, $source, $connection->session_alias, decode_utf8($topic->{Value}));
  }
}

sub me {
  my ($self, $source, $connection, $arg) = @_;
  my $nick = $connection->nick_name;
  $self->http->display_message($nick, $source, $connection->session_alias, decode_utf8("• $arg"));
  $connection->yield("ctcp", $source, "ACTION $1");
}

sub quote {
  my ($self, $source, $connection, $arg) = @_;
  $connection->yield("quote", $arg);
}

sub notfound {
  my ($self, $source, $connection, $arg) = @_;
  $self->http->display_announcement($source, $connection->session_alias,
    "Invalid command $arg");
}

sub _say {
  my ($self, $source, $connection, $arg) = @_;
  my $nick = $connection->nick_name;
  $self->http->display_message($nick, $source, $connection->session_alias, decode_utf8($arg));
  $connection->yield("privmsg", $source, $arg);
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
