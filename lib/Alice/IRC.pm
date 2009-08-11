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

has 'connection' => (
  isa => 'POE::Component::IRC::State',
  is  => 'rw',
  default => sub {{}},
);

has 'alias' => (
  isa => 'Str',
  is => 'ro',
  lazy => 1,
  default => sub {
    return shift->connection->session_alias;
  }
);

has 'app' => (
  isa => 'Alice',
  is  => 'ro',
  required => 1,
);

has 'dispatch' => (
  isa => 'HashRef',
  is => 'ro',
  default => sub {
    {
      _start          => "start",
      irc_public      => "public",
      irc_001         => "connected",
      irc_disconnected => "disconnected",
      irc_join        => "joined",
      irc_part        => "part",
      irc_quit        => "quit",
      irc_chan_sync   => "chan_sync",
      irc_topic       => "topic",
      irc_ctcp_action => "action",
      irc_nick        => "nick",
      irc_msg         => "msg"
    }
  }
);

sub BUILDARGS {
  my ($class, %args) = @_;
  
  my $name = $args{name};
  my $config = $args{config};
  if ($config->{ssl}) {
      eval { require POE::Component::SSLify };
      die "Missing module POE::Component::SSLify" if ($@);
  }
  my $self = {
    app => $args{app},
    connection => POE::Component::IRC::State->spawn(
      alias    => $name,
      nick     => $config->{nick},
      ircname  => $config->{ircname},
      server   => $config->{host},
      port     => $config->{port},
      password => $config->{password},
      username => $config->{username},
      UseSSL   => $config->{ssl},
      msg_length => 1024,
    ),
  };
  return $self;
}

sub BUILD {
  my $self = shift;
  POE::Session->create(
    object_states => [ $self => $self->dispatch ],
  );
}

sub start {
  my $self = $_[OBJECT];
  my $irc = $self->connection;
  $irc->{connector} = POE::Component::IRC::Plugin::Connector->new();
  $irc->plugin_add('Connector' => $irc->{connector});
  $irc->plugin_add('CTCP' => POE::Component::IRC::Plugin::CTCP->new(
    version => 'alice',
    userinfo => $irc->nick_name
  ));
  $irc->plugin_add('NickReclaim' => POE::Component::IRC::Plugin::NickReclaim->new());
  $irc->yield(register => 'all');
  $irc->yield(connect => {});
}

sub window {
  my ($self, $title) = @_;
  return $self->app->window($self->alias, $title);
}

sub config {
  my $self = shift;
  return $self->app->config;
}

sub connected {
  my $self = $_[OBJECT];
  $self->log_info("connected to " . $self->alias);
  for (@{$self->config->{servers}{$self->alias}{channels}}) {
    $self->log_debug("joining $_");
    $self->connection->yield( join => $_ );
  }
  for (@{$self->config->{servers}{$self->alias}{on_connect}}) {
    $self->log_debug("sending $_");
    $self->connection->yield( quote => $_ );
  }
}

sub disconnected {
  my $self = $_[OBJECT];
  $self->log_info("disconnected from " . $self->alias);
}

sub public {
  my ($self, $who, $where, $what) = @_[OBJECT, ARG0 .. ARG2];
  my $nick = ( split /!/, $who )[0];
  my $window = $self->window($where->[0]);
  $what = decode("utf8", $what, Encode::FB_WARN);
  $self->app->send($window->render_message($nick, $what));
}

sub msg {
  my ($self, $who, $what) = @_[OBJECT, ARG0, ARG2];
  my $nick = ( split /!/, $who)[0];
  my $window = $self->window($nick);
  $what = decode("utf8", $what, Encode::FB_WARN);
  $self->app->send($window->render_message($nick, $what));
}

sub action {
  my ($self, $who, $where, $what) = @_[OBJECT, ARG0 .. ARG2];
  my $nick = ( split /!/, $who )[0];
  my $window = $self->window($where->[0]);
  $what = decode("utf8", "• $what", Encode::FB_WARN);
  $self->app->send($window->render_message($nick, $what));
}

sub nick {
  my ($self, $who, $new_nick) = @_[OBJECT, ARG0, ARG1];
  my $nick = ( split /!/, $who )[0];
  my @events = map {
      $self->window($_)->render_event($nick, "nick", $new_nick)
    } $self->connection->nick_channels($new_nick);
  $self->httpd->send(@events)
}

sub joined {
  my ($self, $who, $where) = @_[OBJECT, ARG0, ARG1];
  my $nick = ( split /!/, $who)[0];
  if ($nick ne $self->connection->nick_name) {
    my $window = $self->window($where);
    $self->app->send($window->render_event($nick, "joined"));
  }
  else {
    $self->app->create_window($where, $self->connection);
  }
}

sub chan_sync {
  my ($self, $channel) = @_[OBJECT, ARG0];
  my $window = $self->window($channel);
  return unless $window;
  my $topic = $window->topic;
  if ($topic->{Value} and $topic->{SetBy}) {
    $self->app->send(
      $window->render_event($topic->{SetBy}, "topic", $topic->{Value})
    );
  }
}

sub part {
  my ($self, $who, $where, $msg) = @_[OBJECT, ARG0 .. ARG2];
  my $nick = ( split /!/, $who)[0];
  my $window = $self->window($where);
  if ($nick ne $self->connection->nick_name) {
    $self->app->send($window->render_event($nick, "left", $msg));
  }
  else {
    $self->app->close_window($window);
  }
}

sub quit {
  my ($self, $who, $msg, $channels) = @_[OBJECT, ARG0 .. ARG2];
  my $nick = ( split /!/, $who)[0];
  my @events = map {
    my $window = $self->window($_);
    $window->render_event($nick, "quit", $msg);
  } @$channels;
  $self->app->send(@events);
}

sub topic {
  my ($self, $who, $channel, $topic) = @_[OBJECT, ARG0 .. ARG2];
  my $window = $self->window($channel);
  $self->send($window->render_event($who, "topic", decode_utf8($topic)));
};

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
