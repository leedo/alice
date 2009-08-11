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
      {method => 'part',     re => qr{^/part}},
      {method => 'create',   re => qr{^/create (.+)}},
      {method => 'close',    re => qr{^/close}},
      {method => 'topic',    re => qr{^/topic(?:\s+(.+))?}, in_channel => 1},
      {method => 'me',       re => qr{^/me (.+)}},
      {method => 'quote',    re => qr{^/(?:quote|raw) (.+)}},
      {method => 'notfound', re => qr{^/(.+)(?:\s.*)?}}
    ]
  }
);

has 'app' => (
  is       => 'ro',
  isa      => 'Alice',
  required => 1,
);

sub handle {
  my ($self, $command, $window) = @_;
  for my $handler (@{$self->handlers}) {
    my $re = $handler->{re};
    if ($command =~ /$re/) {
      my $method = $handler->{method};
      my $arg = $1;
      return if ($handler->{in_channel} and ! $window->is_channel);
      $self->$method($window, $arg);
      return;
    }
  }
}

sub names {
  my ($self, $window, $arg) = @_;
  $self->app->send($window->render_announcement($window->nick_table));
}

sub query {
  my ($self, $window, $arg) = @_;
  $self->app->create_window($arg, $window->connection);
}

sub _join {
  my ($self, $window, $arg) = @_;
  $window->connection->yield("join", $arg);
}

sub part {
  my ($self, $window, $arg) = @_;
  if ($window->is_channel) {
    $window->part;
  }
  else {
    $self->app->send($window->render_announceent("Can only /part a channel"));
  }
}

sub close {
  my ($self, $window) = @_;
  if ($window->is_channel) {
    $window->part;
  }
  $self->app->close_window($window);
}

sub create {
  my ($self, $window, $arg) = @_;
  $self->app->create_window($arg, $window->connection);
}

sub topic {
  my ($self, $window, $arg) = @_;
  if ($arg) {
    $window->topic($arg);
  }
  else {
    my $topic = $window->topic;
    $self->app->send($window->render_event("topic", $topic->{SetBy}, decode_utf8($topic->{Value})));
  }
}

sub me {
  my ($self, $window, $arg) = @_;
  $self->app->send($window->render_message($window->nick, decode_utf8("• $arg")));
  $window->connection->yield("ctcp", $window->title, "ACTION $1");
}

sub quote {
  my ($self, $window, $arg) = @_;
  $window->connection->yield("quote", $arg);
}

sub notfound {
  my ($self, $window, $arg) = @_;
  $self->app->send($window->render_announcement("Invalid command $arg"));
}

sub _say {
  my ($self, $window, $arg) = @_;
  $self->app->send($window->render_message($window->nick, decode_utf8($arg)));
  $window->connection->yield("privmsg", $window->title, $arg);
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
