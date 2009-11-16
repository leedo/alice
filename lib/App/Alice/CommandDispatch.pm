package App::Alice::CommandDispatch;

use Moose;
use Encode;
  
has 'handlers' => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub {
    my $self = shift;
    [
      {sub => '_say',     re => qr{^([^/].*)}s},
      {sub => 'query',    re => qr{^/query\s+(\S+)}},
      {sub => 'names',    re => qr{^/n(?:ames)?\s*$}, in_channel => 1},
      {sub => '_join',    re => qr{^/j(?:oin)?\s+(?:-(\S+)\s+)?(\S+)}},
      {sub => 'part',     re => qr{^/part}, in_channel => 1},
      {sub => 'create',   re => qr{^/create (\S+)}},
      {sub => 'close',    re => qr{^/(?:close|wc)}},
      {sub => 'clear',    re => qr{^/clear}},
      {sub => 'topic',    re => qr{^/topic(?:\s+(.+))?}, in_channel => 1},
      {sub => 'whois',    re => qr{^/whois\s+(\S+)}},
      {sub => 'me',       re => qr{^/me (.+)}},
      {sub => 'nick',     re => qr{^/nick\s+(\S+)}},
      {sub => 'quote',    re => qr{^/(?:quote|raw) (.+)}},
      {sub => 'notfound', re => qr{^/(.+)(?:\s.*)?}},
    ]
  }
);

has 'app' => (
  is       => 'ro',
  isa      => 'App::Alice',
  required => 1,
);

sub BUILD {
  shift->meta->error_class('Moose::Error::Croak');
}

sub handle {
  my ($self, $command, $window) = @_;
  for my $handler (@{$self->handlers}) {
    my $re = $handler->{re};
    if ($command =~ /$re/) {
      my @args = grep {defined $_} ($5, $4, $3, $2, $1); # up to 5 captures
      if ($handler->{in_channel} and !$window->is_channel) {
        $self->app->send([
          $window->render_announcement("$command can only be used in a channel")
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
  $self->app->send([$window->render_announcement($window->nick_table)]);
}

sub whois {
  my ($self, $window, $arg) = @_;
  $arg = decode("utf8", $arg, Encode::FB_WARN);
  $self->app->send([$window->render_announcement($window->irc->whois_table($arg))]);
}

sub query {
  my ($self, $window, $arg) = @_;
  $arg = decode("utf8", $arg, Encode::FB_WARN);
  my $new_window = $self->app->find_or_create_window($arg, $window->irc);
  $self->app->send([$new_window->join_action]);
}

sub _join {
  my ($self, $window, $arg1, $arg2) = @_;
  if ($arg2 and $self->app->ircs->{$arg2}) {
    $window = $self->app->ircs->{$arg2};
  }
  if ($arg1 =~ /^[#&]/) {
    $arg1 = decode("utf8", $arg1, Encode::FB_WARN);
    $window->irc->cl->send_srv(JOIN => $arg1);
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
  $arg = decode("utf8", $arg, Encode::FB_WARN);
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
    $window->topic($arg);
  }
  else {
    my $topic = $window->topic;
    my $nick = ( split /!/, $topic->{SetBy} )[0];
    $self->app->send([
      $window->render_event("topic", $nick, $topic->{Value})
    ]);
  }
}

sub me {
  my ($self, $window, $arg) = @_;
  $self->app->send([$window->render_message($window->nick, "• $arg")], 1);
  $window->irc->cl->send_srv(CTCP => $window->title, "ACTION $1");
}

sub quote {
  my ($self, $window, $arg) = @_;
  $arg = decode("utf8", $arg, Encode::FB_WARN);
  $window->irc->cl->send_raw($arg);
}

sub notfound {
  my ($self, $window, $arg) = @_;
  $arg = decode("utf8", $arg, Encode::FB_WARN);
  $self->app->send([$window->render_announcement("Invalid command $arg")]);
}

sub _say {
  my ($self, $window, $arg) = @_;
  $self->app->send([$window->render_message($window->nick, $arg)], 1);
  $arg = decode("utf8", $arg, Encode::FB_WARN);
  $window->irc->cl->send_srv(PRIVMSG => $window->title, $arg);
}

__PACKAGE__->meta->make_immutable;
1;