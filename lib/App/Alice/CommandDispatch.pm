package App::Alice::CommandDispatch;

use Encode;
use Moose;
  
has 'handlers' => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub {
    my $self = shift;
    [
      {sub => '_say',     re => qr{^([^/].*)}s},
      {sub => 'query',    re => qr{^/query\s+(\S+)}},
      {sub => 'names',    re => qr{^/n(?:ames)?\s*$}, in_channel => 1},
      {sub => '_joinpass',re => qr{^/j(?:oin)?\s+(#\S+)\s+(\S+)}},     
      {sub => '_join',    re => qr{^/j(?:oin)?\s+(?:\-(\S+)\s+)?(\S+)(?:\s+(\S+))?}},
      {sub => 'part',     re => qr{^/part}, in_channel => 1},
      {sub => 'create',   re => qr{^/create (\S+)}},
      {sub => 'close',    re => qr{^/(?:close|wc)}},
      {sub => 'clear',    re => qr{^/clear}},
      {sub => 'topic',    re => qr{^/topic(?:\s+(.+))?}, in_channel => 1},
      {sub => 'whois',    re => qr{^/whois\s+(\S+)}},
      {sub => 'me',       re => qr{^/me (.+)}},
      {sub => 'nick',     re => qr{^/nick\s+(\S+)}},
      {sub => 'quote',    re => qr{^/(?:quote|raw) (.+)}},
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
  my ($self, $window, $arg) = @_;
  $arg = decode("utf8", $arg, Encode::FB_QUIET);
  $self->app->send([$window->format_announcement($window->irc->whois_table($arg))]);
}

sub query {
  my ($self, $window, $arg) = @_;
  $arg = decode("utf8", $arg, Encode::FB_QUIET);
  my $new_window = $self->app->find_or_create_window($arg, $window->irc);
  $self->app->send([$new_window->join_action]);
}

sub _join {
  my ($self, $window, $arg1, $arg2, $arg3) = @_;
  my $irc = $window->irc;
  if ($arg2 and $self->app->ircs->{$arg2}) {
    $irc = $self->app->ircs->{$arg2};
  }
  if ($irc and $arg1 =~ /^[#&]/) {
    $self->app->send([$irc->log_info("joining $arg1")]);
    $irc->cl->send_srv(JOIN => $arg1);
  }
}

sub _joinpass {
  my ($self, $window, $password, $channel) = @_;
  my $irc = $window->irc;
  if($irc and $channel =~ /^[#&]/) {
    $self->app->send([$irc->log_info("joining $channel with password $password")]);
    $irc->cl->send_srv(JOIN => $channel, $password);
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
  my ($self, $window, $arg) = @_;
  $window->irc->send_srv(NICK => $arg);
}

sub create {
  my ($self, $window, $arg) = @_;
  return unless $window->irc;
  $arg = decode("utf8", $arg, Encode::FB_QUIET);
  my $new_window = $self->app->find_or_create_window($arg, $window->irc);
  $self->app->send([$new_window->join_action]);
}

sub clear {
  my ($self, $window, $arg) = @_;
  $window->clear_buffer;
  $self->app->send([$window->clear_action]);
}

sub topic {
  my ($self, $window, $arg) = @_;
  if ($arg) {
    $window->set_topic($arg);
  }
  else {
    my $topic = $window->topic;
    $self->app->send([
      $window->format_event("topic", $topic->{author}, $topic->{string})
    ]);
  }
}

sub me {
  my ($self, $window, $arg) = @_;
  $self->app->send([$window->format_message($window->nick, "• $arg")], 1);
  $window->irc->cl->send_srv(CTCP => $window->title, "ACTION $1");
}

sub quote {
  my ($self, $window, $arg) = @_;
  $arg = decode("utf8", $arg, Encode::FB_QUIET);
  $window->irc->cl->send_raw($arg);
}

sub disconnect {
  my ($self, $window, $arg) = @_;
  my $irc = $self->app->ircs->{$arg};
  if ($irc and $irc->is_connected) {
    $irc->disconnect;
  }
}

sub connect {
  my ($self, $window, $arg) = @_;
  my $irc  = $self->app->ircs->{$arg};
  if ($irc and !$irc->is_connected) {
    $irc->connect;
  }
}

sub ignores {
  my ($self, $window, $arg) = @_;
  my $msg = join ", ", $self->app->ignores;
  $msg = "none" unless $msg;
  $self->app->send([
    $window->format_announcement("Ignoring:\n$msg")
  ]);
}

sub ignore {
  my ($self, $window, $arg) = @_;
  $self->app->add_ignore($arg);
  $self->app->send([$window->format_announcement("Ignoring $arg")]);
}

sub unignore {
  my ($self, $window, $arg) = @_;
  $self->app->remove_ignore($arg);
  $self->app->send([$window->format_announcement("No longer ignoring $arg")]);
}

sub notfound {
  my ($self, $window, $arg) = @_;
  $self->app->send([$window->format_announcement("Invalid command $arg")]);
}

sub _say {
  my ($self, $window, $arg) = @_;
  $self->app->send([$window->format_message($window->nick, $arg)]);
  $arg = decode("utf8", $arg, Encode::FB_QUIET);
  $window->irc->cl->send_srv(PRIVMSG => $window->title, $arg);
}

__PACKAGE__->meta->make_immutable;
1;
