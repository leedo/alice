package App::Alice::CommandDispatch;

use Any::Moose;
  
has 'handlers' => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub {
    my $self = shift;
    [
      {sub => '_say',     re => qr{^([^/].*)}s},
      {sub => 'query',    re => qr{^/query\s+(\S+)}},
      {sub => 'nick',     re => qr{^/nick\s+(\S+)}},
      {sub => 'names',    re => qr{^/n(?:ames)?}, in_channel => 1},
      {sub => '_join',    re => qr{^/j(?:oin)?\s+(?:\-(\S+)\s+)?(.+)}},
      {sub => 'part',     re => qr{^/part}, in_channel => 1},
      {sub => 'create',   re => qr{^/create\s+(\S+)}},
      {sub => 'close',    re => qr{^/(?:close|wc)}},
      {sub => 'clear',    re => qr{^/clear}},
      {sub => 'topic',    re => qr{^/topic(?:\s+(.+))?}, in_channel => 1},
      {sub => 'whois',    re => qr{^/whois\s+(\S+)}},
      {sub => 'me',       re => qr{^/me\s+(.+)}},
      {sub => 'quote',    re => qr{^/(?:quote|raw)\s+(.+)}},
      {sub => 'disconnect',re=> qr{^/disconnect\s+(\S+)}},
      {sub => 'connect',  re => qr{^/connect\s+(\S+)}},
      {sub => 'ignore',   re => qr{^/ignore\s+(\S+)}},
      {sub => 'unignore', re => qr{^/unignore\s+(\S+)}},
      {sub => 'ignores',  re => qr{^/ignores?}},
      {sub => 'notfound', re => qr{^/(.+)(?:\s.*)?}},
    ]
  }
);

has 'app' => (
  is       => 'ro',
  isa      => 'App::Alice',
  required => 1,
);

sub handle {
  my ($self, $command, $window) = @_;
  for my $handler (@{$self->handlers}) {
    my $re = $handler->{re};
    if ($command =~ /$re/) {
      my @args = grep {defined $_} ($5, $4, $3, $2, $1); # up to 5 captures
      if ($handler->{in_channel} and !$window->is_channel) {
        $self->app->send([
          $window->format_announcement("$command can only be used in a channel")
        ]);
      }
      else {
        my $sub = $handler->{sub};
        if ($self->meta->find_method_by_name($sub)) {
          $self->$sub($window, @args);
        }
        else {
          $self->app->send($self->app->log_info(
            "Error handling $command: $sub sub not found"));
        }
      }
      return;
    }
  }
}

sub names {
  my ($self, $window) = @_;
  $self->app->send([$window->format_announcement($window->nick_table)]);
}

sub whois {
  my ($self, $window, $nick) = @_;
  $self->app->send([$window->format_announcement($window->irc->whois_table($nick))]);
}

sub query {
  my ($self, $window, $nick) = @_;
  my $new_window = $self->app->find_or_create_window($nick, $window->irc);
  $self->app->send([$new_window->join_action]);
}

sub _join {
  my ($self, $window, $channel, $network) = @_;
  my $irc = $window->irc;
  if ($network and $self->app->ircs->{$network}) {
    $irc = $self->app->ircs->{$network};
  }
  my @params = split /\s+/, $channel;
  if ($irc and $irc->cl->is_channel_name($params[0])) {
    $self->app->send([$irc->log_info("joining $params[0]")]);
    $irc->cl->send_srv(JOIN => @params);
  }
}

sub part {
  my ($self, $window) = @_;
  $window->part if $window->is_channel;
}

sub close {
  my ($self, $window) = @_;
  $window->is_channel ?
    $window->part : $self->app->close_window($window);
}

sub nick {
  my ($self, $window, $nick) = @_;
  $window->irc->cl->send_srv(NICK => $nick);
}

sub create {
  my ($self, $window, $name) = @_;
  my $new_window = $self->app->find_or_create_window($name, $window->irc);
  $self->app->send([$new_window->join_action]);
}

sub clear {
  my ($self, $window) = @_;
  $window->clear_buffer;
  $self->app->send([$window->clear_action]);
}

sub topic {
  my ($self, $window, $new_topic) = @_;
  if ($new_topic) {
    $window->set_topic($new_topic);
  }
  else {
    my $topic = $window->topic;
    $self->app->send([
      $window->format_event("topic", $topic->{author}, $topic->{string})
    ]);
  }
}

sub me {
  my ($self, $window, $action) = @_;
  $self->app->send([$window->format_message($window->nick, "• $action")]);
  $window->irc->cl->send_srv(PRIVMSG => $window->title, chr(01) . "ACTION $action" . chr(01));
}

sub quote {
  my ($self, $window, $commands) = @_;
  $window->irc->cl->send_raw(split /\s+/, $commands);
}

sub disconnect {
  my ($self, $window, $network) = @_;
  my $irc = $self->app->ircs->{$network};
  if ($irc and $irc->is_connected) {
    $irc->disconnect;
  }
}

sub connect {
  my ($self, $window, $network) = @_;
  my $irc  = $self->app->ircs->{$network};
  if ($irc and !$irc->is_connected) {
    $irc->connect;
  }
}

sub ignores {
  my ($self, $window) = @_;
  my $msg = join ", ", $self->app->ignores;
  $msg = "none" unless $msg;
  $self->app->send([
    $window->format_announcement("Ignoring:\n$msg")
  ]);
}

sub ignore {
  my ($self, $window, $nick) = @_;
  $self->app->add_ignore($nick);
  $self->app->send([$window->format_announcement("Ignoring $nick")]);
}

sub unignore {
  my ($self, $window, $nick) = @_;
  $self->app->remove_ignore($nick);
  $self->app->send([$window->format_announcement("No longer ignoring $nick")]);
}

sub notfound {
  my ($self, $window, $command) = @_;
  $self->app->send([$window->format_announcement("Invalid command $command")]);
}

sub _say {
  my ($self, $window, $msg) = @_;
  $self->app->send([$window->format_message($window->nick, $msg)]);
  $window->irc->cl->send_srv(PRIVMSG => $window->title, $msg);
}

__PACKAGE__->meta->make_immutable;
1;
