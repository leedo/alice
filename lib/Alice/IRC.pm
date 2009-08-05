package Alice::IRC;

use strict;
use warnings;

use POE;
use POE::Component::IRC;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::Connector;
use Encode;
use Moose;

has 'connection_map' => (
  isa => 'HashRef[POE::Component::IRC::State]',
  is  => 'rw',
  default => sub {{}},
);

has 'config' => (
  isa => 'HashRef',
  is  => 'rw',
  required => 1,
);

has 'httpd' => (
  isa => 'Alice::HTTPD',
  is  => 'ro',
  weak_ref => 1,
  required => 1,
  trigger => sub {
    my $self = shift;
    $self->httpd->irc($self);
  },
);

has session => is => 'rw';

sub BUILD {
  my $self = shift;
  $self->add_server($_, $self->config->{servers}{$_})
    for keys %{$self->config->{servers}};
}

sub connection {
  my ($self, $session_id) = @_;
  return $self->connection_map->{$session_id};
}

sub connections {
  my $self = shift;
  return values %{$self->connection_map};
}

sub add_server {
  my ($self, $name, $server) = @_;
  my $irc = POE::Component::IRC::State->spawn(
    alias    => $name,
    nick     => $server->{nick},
    ircname  => $server->{ircname},
    server   => $server->{host},
    port     => $server->{port},
    password => $server->{password},
    username => $server->{username},
    UseSSL   => $server->{ssl},
  );
  POE::Session->create(
    object_states => [
      $self => {_start          => "start"},
      $self => {irc_public      => "public"},
      $self => {irc_001         => "connected"},
      $self => {irc_disconnected => "disconnected"},
      $self => {irc_join        => "joined"},
      $self => {irc_part        => "part"},
      $self => {irc_quit        => "quit"},
      $self => {irc_chan_sync   => "chan_sync"},
      $self => {irc_topic       => "topic"},
      $self => {irc_ctcp_action => "action"},
      $self => {irc_nick        => "nick"},
      $self => {irc_msg         => "msg"},
    ],
    heap => {irc => $irc}
  );
  $self->connection_map->{$irc->session_id} = $irc;
  return $irc;
}

sub start {
  my $self = $_[OBJECT];
  my $irc = $_[HEAP]->{irc};
  $irc->{connector} = POE::Component::IRC::Plugin::Connector->new();
  $irc->plugin_add('Connector' => $irc->{connector});
  $irc->yield(register => 'all');
  $irc->yield(connect => {});
  $_[HEAP] = undef;
}

sub connected {
  my $self = $_[OBJECT];
  my $irc = $self->connection($_[SENDER]->ID);
  $self->log_info("connected to " . $irc->{alias});
  for (@{$self->config->{servers}{$irc->{alias}}{channels}}) {
    $self->log_debug("joining $_");
    $irc->yield( join => $_ );
  }
}

sub disconnected {
  my $self = $_[OBJECT];
  my $irc = $self->connection($_[SENDER]->ID);
  $self->log_info("disconnected from " . $irc->{alias});
}

sub public {
  my ($self, $who, $where, $what) = @_[OBJECT, ARG0 .. ARG2];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who )[0];
  my $channel = $where->[0];
  $what = decode("utf8", $what, Encode::FB_WARN);
  $self->httpd->display_message($nick, $channel, $irc->session_id, $what);
}

sub msg {
  my ($self, $who, $what) = @_[OBJECT, ARG0, ARG2];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who)[0];
  $what = decode("utf8", $what, Encode::FB_WARN);
  $self->httpd->display_message($nick, $nick, $irc->session_id, $what);
}

sub action {
  my ($self, $who, $where, $what) = @_[OBJECT, ARG0 .. ARG2];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who )[0];
  my $channel = $where->[0];
  $what = decode("utf8", "• $what", Encode::FB_WARN);
  $self->httpd->display_message($nick, $channel, $irc->session_id, $what);
}

sub nick {
  my ($self, $who, $new_nick) = @_[OBJECT, ARG0, ARG1];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who )[0];
  $self->httpd->display_event($nick, $_, $irc->session_id, "nick", $new_nick)
    for $irc->nick_channels($new_nick);
}

sub joined {
  my ($self, $who, $where) = @_[OBJECT, ARG0, ARG1];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who)[0];
  my $channel = $where;
  if ($nick ne $irc->nick_name) {
    $self->httpd->display_event($nick, $channel, $irc->session_id, "joined");  
  }
  else {
    $self->httpd->create_tab($channel, $irc->session_id);
  }
}

sub chan_sync {
  my ($self, $channel) = @_[OBJECT, ARG0];
  my $irc = $self->connection($_[SENDER]->ID);
  $self->httpd->create_tab($channel, $irc->session_id) if $channel ne "main";
  my $topic = $irc->channel_topic($channel);
  if ($topic->{Value} and $topic->{SetBy}) {
    $self->httpd->send_topic(
      $topic->{SetBy}, $channel, $irc->session_id, decode_utf8($topic->{Value})
    );
  }
}

sub part {
  my ($self, $who, $where, $msg) = @_[OBJECT, ARG0 .. ARG2];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who)[0];
  my $channel = $where;
  if ($nick ne $irc->nick_name) {
    $self->httpd->display_event($nick, $channel, $irc->session_id, "left", $msg);
  }
  else {
    $self->httpd->close_tab($channel, $irc->session_id);
  }
}

sub quit {
  my ($self, $who, $msg, $channels) = @_[OBJECT, ARG0 .. ARG2];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who)[0];
  for my $channel (@$channels) {
    $self->httpd->display_event($nick, $channel, $irc->session_id, "left", $msg);
  }
}

sub topic {
  my ($self, $who, $channel, $topic) = @_[OBJECT, ARG0 .. ARG2];
  my $irc = $self->connection($_[SENDER]->ID);
  $self->httpd->send_topic($who, $channel, $irc->session_id, $topic);
}

sub log_debug {
  my $self = shift;
  print STDERR join " ", @_, "\n" if $self->config->{debug};
}

sub log_info {
  my $self = shift;
  print STDERR join " ", @_, "\n";
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
