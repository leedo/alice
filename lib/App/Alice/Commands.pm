package App::Alice::Commands;

use Any::Moose;
use Encode;

has 'handlers' => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub {[]},
);

has 'app' => (
  is       => 'ro',
  isa      => 'App::Alice',
  weak_ref => 1,
  required => 1,
);

sub BUILD {
  my $self = shift;
  $self->reload_handlers;
}

sub reload_handlers {
  my $self = shift;
  my $commands_file = $self->app->config->assetdir . "/commands.pl";
  if (-e $commands_file) {
    my $commands = do $commands_file;
    if ($commands and ref $commands eq "ARRAY") {
      $self->handlers($commands) if $commands;
    }
  }
}

sub handle {
  my ($self, $command, $window) = @_;
  for my $handler (@{$self->handlers}) {
    my $re = $handler->{re};
    if ($command =~ /$re/) {
      my @args = grep {defined $_} ($5, $4, $3, $2, $1); # up to 5 captures
      if ($handler->{in_channel} and !$window->is_channel) {
        $self->reply($window, "$command can only be used in a channel");
      }
      else {
        my $sub = $handler->{sub};
        if ($self->meta->find_method_by_name($sub)) {
          $self->$sub($window, @args);
        }
        else {
          $self->reply($window, "Error handling $command: $sub sub not found");
        }
      }
      return;
    }
  }
}

sub help {
  my ($self, $window, $command) = @_;
  if (!$command) {
    $self->reply($window, '/HELP <command> for help with a specific command');
    $self->reply($window, "Available commands: " . join " ", map {
      my $name = $_->{sub};
      $name =~ s/^_//;
      uc $name;
    } grep {$_->{eg}} @{$self->handlers});
    return;
  }
  for (@{$self->handlers}) {
    my $name = $_->{sub};
    $name =~ s/^_//;
    if ($name eq lc $command) {
      $self->reply($window, "$_->{eg}\n$_->{desc}");
      return;
    }
  }
  $self->reply($window, "No help for ".uc $command);
}

sub names {
  my ($self, $window, $avatars) = @_;
  $self->reply($window, $window->nick_table($avatars));
}

sub whois {
  my ($self, $window, $nick, $force) = @_;
  if (!$force and $window->irc->includes_nick($nick)) {
    $self->reply($window, $window->irc->whois_table($nick));
  }
  else {
    $window->irc->add_whois_cb($nick => sub {
      $self->reply($window, $window->irc->whois_table($nick));
    });
  }
}

sub msg {
  my $self = shift;
  my $window = shift;
  my ($msg, $nick, $network);
  if (@_ == 3) {
    ($msg, $nick, $network) = @_;
  }
  elsif (@_ == 2) {
    ($msg, $nick) = @_;
  }
  $msg =~ s/^\s+//;
  my $irc = $window->irc;
  if ($network and $self->app->has_irc($network)) {
    $irc = $self->app->get_irc($network);
  }
  return unless $irc;
  my $new_window = $self->app->find_or_create_window($nick, $irc);
  my @msgs = ($new_window->join_action);
  if ($msg) {
    push @msgs, $new_window->format_message($new_window->nick, $msg);
    $irc->send_srv(PRIVMSG => $nick, $msg) if $msg;
  }
  $self->broadcast(@msgs);
}

sub _join {
  my ($self, $window, $channel, $network) = @_;
  my $irc;
  if ($network and $self->app->has_irc($network)) {
    $irc = $self->app->get_irc($network);
  } else {
    $irc = $window->irc;
  }
  my @params = split /\s+/, $channel;
  if ($irc and $irc->cl->is_channel_name($params[0])) {
    $irc->log(info => "joining $params[0]");
    $irc->send_srv(JOIN => @params);
  }
}

sub part {
  my ($self, $window) = @_;
  $window->is_channel ? $window->irc->send_srv(PART => $window->title)
                      : $self->app->close_window($window);
}

sub nick {
  my ($self, $window, $nick, $network) = @_;
  my $irc;
  if ($network and $self->app->has_irc($network)) {
    $irc = $self->app->get_irc($network);
  } else {
    $irc = $window->irc;
  }
  $irc->log(info => "now known as $nick");
  $irc->send_srv(NICK => $nick);
}

sub create {
  my ($self, $window, $name) = @_;
  my $new_window = $self->app->find_or_create_window($name, $window->irc);
  $self->broadcast($new_window->join_action);
}

sub clear {
  my ($self, $window) = @_;
  $window->buffer->clear;
  $self->broadcast($window->clear_action);
}

sub topic {
  my ($self, $window, $new_topic) = @_;
  if ($new_topic) {
    $window->topic({string => $new_topic, nick => $window->nick, time => time});
    $window->irc->send_srv(TOPIC => $window->title, $new_topic);
  }
  else {
    my $topic = $window->topic;
    $self->broadcast($window->format_event("topic", $topic->{author}, $topic->{string}));
  }
}

sub me {
  my ($self, $window, $action) = @_;
  $self->show($window, "• $action");
  $window->irc->send_srv(PRIVMSG => $window->title, chr(01) . "ACTION $action" . chr(01));
}

sub quote {
  my ($self, $window, $command) = @_;
  $window->irc->send_raw($command);
}

sub disconnect {
  my ($self, $window, $network) = @_;
  my $irc = $self->app->get_irc($network);
  if ($irc and $irc->is_connected) {
    $irc->disconnect;
  }
  elsif ($irc->reconnect_timer) {
    $irc->cancel_reconnect;
    $irc->log(info => "canceled reconnect");
  }
  else {
    $self->reply($window, "already disconnected");
  }
}

sub connect {
  my ($self, $window, $network) = @_;
  my $irc  = $self->app->get_irc($network);
  if ($irc and !$irc->is_connected) {
    $irc->connect;
  }
}

sub ignores {
  my ($self, $window) = @_;
  my $msg = join ", ", $self->app->ignores;
  $msg = "none" unless $msg;
  $self->reply($window, "Ignoring:\n$msg");
}

sub ignore {
  my ($self, $window, $nick) = @_;
  $self->app->add_ignore($nick);
  $self->reply($window, "Ignoring $nick");
}

sub unignore {
  my ($self, $window, $nick) = @_;
  $self->app->remove_ignore($nick);
  $self->reply($window, "No longer ignoring $nick");
}

sub window {
  my ($self, $window, $window_number) = @_;
  $self->broadcast({
    type => "action",
    event => "focus",
    window_number => $window_number,
  });
}

sub notfound {
  my ($self, $window, $command) = @_;
  $self->reply($window, "Invalid command $command");
}

sub _say {
  my ($self, $window, $msg) = @_;
  if ($window->type eq "info") {
    $self->reply($window, "You can't talk here!");
    return;
  }
  elsif (!$window->irc->is_connected) {
    $self->reply($window, "You are not connected to ".$window->irc->alias.".");
    return;
  }
  $self->app->store(nick => $window->nick, channel => $window->title, body => $msg);
  $self->show($window, $msg);
  $window->irc->send_srv(PRIVMSG => $window->title, $msg);
}

sub show {
  my ($self, $window, $message) = @_;
  $self->broadcast($window->format_message($window->nick, $message));
}

sub reply {
  my ($self, $window, $message) = @_;
  $self->broadcast($window->format_announcement($message));
}

sub broadcast {
  my ($self, @messages) = @_;
  $self->app->broadcast(@messages);
}

__PACKAGE__->meta->make_immutable;
1;
