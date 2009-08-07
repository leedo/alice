package Alice::IRC;

use strict;
use warnings;

use POE;
use POE::Component::IRC;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Plugin::CTCP;
use POE::Component::IRC::Plugin::NickReclaim;
use Encode;
use Moose;

has 'connection_alias_map' => (
  isa => 'HashRef[POE::Component::IRC::State]',
  is  => 'rw',
  default => sub {{}},
);

has 'connection_id_map' => (
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
  return $self->connection_id_map->{$session_id};
}

sub connection_from_alias {
  my ($self, $session_alias) = @_;
  return $self->connection_alias_map->{$session_alias};
}

sub connections {
  my $self = shift;
  return values %{$self->connection_id_map};
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
    msg_length => 1024,
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
  $self->connection_alias_map->{$name} = $irc;
  $self->connection_id_map->{$irc->session_id} = $irc;
  return $irc;
}

sub start {
  my $self = $_[OBJECT];
  my $irc = $_[HEAP]->{irc};
  $irc->{connector} = POE::Component::IRC::Plugin::Connector->new();
  $irc->plugin_add('Connector' => $irc->{connector});
  $irc->plugin_add('CTCP' => POE::Component::IRC::Plugin::CTCP->new(
    version => 'alice',
    userinfo => $irc->nick_name
  ));
  $irc->plugin_add('NickReclaim' => POE::Component::IRC::Plugin::NickReclaim->new());
  $irc->yield(register => 'all');
  $irc->yield(connect => {});
  $_[HEAP] = undef;
}

sub connected {
  my $self = $_[OBJECT];
  my $irc = $self->connection($_[SENDER]->ID);
  my $session_alias = $irc->session_alias;
  $self->log_info("connected to $session_alias");
  for (@{$self->config->{servers}{$session_alias}{channels}}) {
    $self->log_debug("joining $_");
    $irc->yield( join => $_ );
  }
  for (@{$self->config->{servers}{$session_alias}{on_connect}}) {
    $self->log_debug("sending $_");
    $irc->yield( quote => $_ );
  }
}

sub disconnected {
  my $self = $_[OBJECT];
  my $irc = $self->connection($_[SENDER]->ID);
  $self->log_info("disconnected from " . $irc->session_alias);
}

sub public {
  my ($self, $who, $where, $what) = @_[OBJECT, ARG0 .. ARG2];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who )[0];
  my $channel = $where->[0];
  $what = decode("utf8", $what, Encode::FB_WARN);
  $self->httpd->display_message($nick, $channel, $irc->session_alias, $what);
}

sub msg {
  my ($self, $who, $what) = @_[OBJECT, ARG0, ARG2];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who)[0];
  $what = decode("utf8", $what, Encode::FB_WARN);
  $self->httpd->display_message($nick, $nick, $irc->session_alias, $what);
}

sub action {
  my ($self, $who, $where, $what) = @_[OBJECT, ARG0 .. ARG2];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who )[0];
  my $channel = $where->[0];
  $what = decode("utf8", "• $what", Encode::FB_WARN);
  $self->httpd->display_message($nick, $channel, $irc->session_alias, $what);
}

sub nick {
  my ($self, $who, $new_nick) = @_[OBJECT, ARG0, ARG1];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who )[0];
  $self->httpd->display_event($nick, $_, $irc->session_alias, "nick", $new_nick)
    for $irc->nick_channels($new_nick);
}

sub joined {
  my ($self, $who, $where) = @_[OBJECT, ARG0, ARG1];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who)[0];
  my $channel = $where;
  if ($nick ne $irc->nick_name) {
    $self->httpd->display_event($nick, $channel, $irc->session_alias, "joined");  
  }
  else {
    $self->httpd->create_tab($channel, $irc->session_alias);
  }
}

sub chan_sync {
  my ($self, $channel) = @_[OBJECT, ARG0];
  my $irc = $self->connection($_[SENDER]->ID);
  my $topic = $irc->channel_topic($channel);
  if ($topic->{Value} and $topic->{SetBy}) {
    $self->httpd->send_topic(
      $topic->{SetBy}, $channel, $irc->session_alias, decode_utf8($topic->{Value}), $topic->{SetAt}
    );
  }
}

sub part {
  my ($self, $who, $where, $msg) = @_[OBJECT, ARG0 .. ARG2];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who)[0];
  my $channel = $where;
  if ($nick ne $irc->nick_name) {
    $self->httpd->display_event($nick, $channel, $irc->session_alias, "left", $msg);
  }
  else {
    $self->httpd->close_tab($channel, $irc->session_alias);
  }
}

sub quit {
  my ($self, $who, $msg, $channels) = @_[OBJECT, ARG0 .. ARG2];
  my $irc = $self->connection($_[SENDER]->ID);
  my $nick = ( split /!/, $who)[0];
  for my $channel (@$channels) {
    $self->httpd->display_event($nick, $channel, $irc->session_alias, "left", $msg);
  }
}

sub topic {
  my ($self, $who, $channel, $topic) = @_[OBJECT, ARG0 .. ARG2];
  my $irc = $self->connection($_[SENDER]->ID);
  $self->httpd->send_topic($who, $channel, $irc->session_alias, decode_utf8($topic));
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
