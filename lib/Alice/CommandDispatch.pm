package Alice::CommandDispatch;

use Moose;
use Encode;

use strict;
use warnings;

has 'handlers' => (
  is => 'rw',
  isa => 'HashRef',
  default => sub {
    my $self = shift;
    {
      '_join'      => qr{^/j(?:oin)? (.+)},
      'part'       => qr{^/part},
      'query'      => qr{^/query},
      'new_window' => qr{^/window new (.+)},
      'names'      => qr{^/n(?:ames)?},
      'topic'      => qr{^/topic (.+)},
      'me'         => qr{^/me (.+)},
      'quote'      => qr{^/(?:quote|raw) (.+)},
      '_say'       => qr{^([^/].+)}
    }
  }
);

has 'http' => (
  is       => 'ro',
  isa      => 'Alice::HTTPD',
  required => 1,
);

sub handle {
  my ($self, $command, $channel, $connection) = @_;
  for my $method (keys %{$self->handlers}) {
    my $re = $self->handlers->{$method};
    if ($command =~ /$re/) {
      $self->$method($channel, $connection, $1);
      last;
    }
  }
}

sub query {
  my ($self, $chan, $connection, $arg) = @_;
  $self->http->create_tab($arg, $connection->session_alias);
}

sub _join {
  my ($self, $chan, $connection, $arg) = @_;
  $connection->yield("join", $arg);
}

sub part {
  my ($self, $chan, $connection, $arg) = @_;
  $connection->yield("part", $arg || $chan);
}

sub new_window {
  my ($self, $chan, $connection, $arg) = @_;
  $self->http->create_tab($arg, $connection->session_alias);
}

sub topic {
  my ($self, $chan, $connection, $arg) = @_;
  if ($arg) {
    $connection->yield("topic", $chan, $arg);
  }
  else {
    my $topic = $connection->channel_topic($chan);
    $self->http->send_topic(
      $topic->{SetBy}, $chan, $connection->session_alias, decode_utf8($topic->{Value}));
  }
}

sub me {
  my ($self, $chan, $connection, $arg) = @_;
  $self->http->display_message($arg, $chan, $connection->session_alias, decode_utf8("• $1"));
  $connection->yield("ctcp", $chan, "ACTION $1");
}

sub quote {
  my ($self, $chan, $connection, $arg) = @_;
  $connection->yield("quote", $arg);
}

sub announce {
  my ($self, $chan, $connection, $arg) = @_;
  $self->http->display_announcement($chan, $connection->session_alias,
    "Invalid command $arg");
}

sub _say {
  my ($self, $chan, $connection, $arg) = @_;
  my $nick = $connection->nick_name;
  $self->http->display_message($nick, $chan, $connection->session_alias, decode_utf8($arg));
  $connection->yield("privmsg", $chan, $arg);
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;