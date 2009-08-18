use MooseX::Declare;

class Alice::CommandDispatch {
  
  use Encode;
  
  has 'handlers' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub {
      my $self = shift;
      [
        {method => '_say',     re => qr{^([^/].*)}s},
        {method => 'query',    re => qr{^/query\s+(.+)}},
        {method => 'names',    re => qr{^/n(?:ames)?}, in_channel => 1},
        {method => '_join',    re => qr{^/j(?:oin)?\s+(.+)}},
        {method => 'part',     re => qr{^/part}, in_channel => 1},
        {method => 'create',   re => qr{^/create (.+)}},
        {method => 'close',    re => qr{^/close}},
        {method => 'topic',    re => qr{^/topic(?:\s+(.+))?}, in_channel => 1},
        {method => 'whois',    re => qr{^/whois (.+)}},
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

  method handle (Str $command, Alice::Window $window) {
    for my $handler (@{$self->handlers}) {
      my $re = $handler->{re};
      if ($command =~ /$re/) {
        my $arg = $1;
        if ($handler->{in_channel} and ! $window->is_channel) {
          $self->app->send(
            $window->render_announcement("$command can only be used in a channel")
          );
        }
        else {
          my $method = $handler->{method};
          $self->$method($window, $arg);
        }
        return;
      }
    }
  }

  method names (Alice::Window $window, $?) {
    $self->app->send($window->render_announcement($window->nick_table));
  }

  method whois (Alice::Window $window, Str $arg) {
    $self->app->send($window->render_announcement($window->nick_info($arg)));
  }

  method query (Alice::Window $window, Str $arg) {
    $self->app->create_window($arg, $window->connection);
  }

  method _join (Alice::Window $window, Str $arg) {
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    $window->connection->yield("join", $arg);
  }

  method part (Alice::Window $window, $?) {
    if ($window->is_channel) {
      $window->part;
    }
  }

  method close (Alice::Window $window, $?) {
    if ($window->is_channel) {
      $window->part;
    }
    else {
      $self->app->close_window($window);
    }
  }

  method create (Alice::Window $window, Str $arg) {
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    $self->app->create_window($arg, $window->connection);
  }

  method topic (Alice::Window $window, Str $arg?) {
    if ($arg) {
      $window->topic($arg);
    }
    else {
      my $topic = $window->topic;
      $self->app->send(
        $window->render_event("topic", $topic->{SetBy}, $topic->{Value})
      );
    }
  }

  method me (Alice::Window $window, Str $arg) {
    $self->app->send($window->render_message($window->nick, "• $arg"));
    $window->connection->yield("ctcp", $window->title, "ACTION $1");
  }

  method quote (Alice::Window $window, Str $arg) {
    $window->connection->yield("quote", $arg);
  }

  method notfound (Alice::Window $window, Str $arg) {
    $self->app->send($window->render_announcement("Invalid command $arg"));
  }

  method _say (Alice::Window $window, Str $arg) {
    $self->app->send($window->render_message($window->nick, $arg));
    $window->connection->yield("privmsg", $window->title, $arg);
  }
}
