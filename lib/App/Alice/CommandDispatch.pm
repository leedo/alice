package App::Alice::CommandDispatch;

use Any::Moose;
use Encode;
my $SRVOPT = qr/(?:\-(\S+)\s+)?/;

has 'handlers' => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub {
    my $self = shift;
    [
      {sub => '_say',     re => qr{^([^/].*)}s},
      {sub => 'msg',      re => qr{^/(?:msg|query)\s+$SRVOPT(\S+)(.*)}},
      {sub => 'nick',     re => qr{^/nick\s+(\S+)}},
      {sub => 'names',    re => qr{^/n(?:ames)?}, in_channel => 1},
      {sub => '_join',    re => qr{^/j(?:oin)?\s+$SRVOPT(.+)}},
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

sub names {
  my ($self, $window) = @_;
  $self->reply($window, $window->nick_table);
}

sub whois {
  my ($self, $window, $nick) = @_;
  $self->reply($window, $window->irc->whois_table($nick));
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
  my $irc = $window->irc;
  if ($network and $self->app->has_irc($network)) {
    $irc = $self->app->get_irc($network);
  }
  my @params = split /\s+/, $channel;
  if ($irc and $irc->cl->is_channel_name($params[0])) {
    $irc->log(info => "joining $params[0]");
    $irc->send_srv(JOIN => @params);
  }
}

sub part {
  my ($self, $window) = @_;
  $window->part if $window->is_channel;
}

sub close {
  my ($self, $window) = @_;
  $window->is_channel ? $window->irc->send_srv(PART => $window->title)
                      : $self->app->close_window($window);
}

sub nick {
  my ($self, $window, $nick) = @_;
  $window->irc->send_srv(NICK => $nick);
}

sub create {
  my ($self, $window, $name) = @_;
  my $new_window = $self->app->find_or_create_window($name, $window->irc);
  $self->broadcast($new_window->join_action);
}

sub clear {
  my ($self, $window) = @_;
  $window->clear_buffer;
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

sub notfound {
  my ($self, $window, $command) = @_;
  $self->reply($window, "Invalid command $command");
}

sub _say {
  my ($self, $window, $msg) = @_;
  $self->app->store($window->nick, $window->title, $msg);
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
