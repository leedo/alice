use MooseX::Declare;

class App::Alice::CommandDispatch {
  
  use Encode;
  
  has 'handlers' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub {
      my $self = shift;
      [
        {method => '_say',     re => qr{^([^/].*)}s},
        {method => 'query',    re => qr{^/query\s+(.+)\s?}},
        {method => 'names',    re => qr{^/n(?:ames)?}, in_channel => 1},
        {method => '_join',    re => qr{^/j(?:oin)?\s+(.+)\s?}},
        {method => 'part',     re => qr{^/part}, in_channel => 1},
        {method => 'create',   re => qr{^/create (.+)\s?}},
        {method => 'close',    re => qr{^/close}},
        {method => 'clear',    re => qr{^/clear}},
        {method => 'topic',    re => qr{^/topic(?:\s+(.+))?}, in_channel => 1},
        {method => 'whois',    re => qr{^/whois\s+(.+)\s?}},
        {method => 'me',       re => qr{^/me (.+)}},
        {method => 'quote',    re => qr{^/(?:quote|raw) (.+)}},
        {method => 'notfound', re => qr{^/(.+)(?:\s.*)?}}
      ]
    }
  );

  has 'app' => (
    is       => 'ro',
    isa      => 'App::Alice',
    required => 1,
  );

  method handle (Str $command, App::Alice::Window $window) {
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

  method names (App::Alice::Window $window, $?) {
    $self->app->send($window->render_announcement($window->nick_table));
  }

  method whois (App::Alice::Window $window, Str $arg) {
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    $self->app->send($window->render_announcement($window->whois_table($arg)));
  }

  method query (App::Alice::Window $window, Str $arg) {
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    my $new_window = $self->app->find_or_create_window($arg, $window->connection);
    $self->app->send($new_window->join_action);
  }

  method _join (App::Alice::Window $window, Str $arg) {
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    $window->connection->yield("join", $arg);
  }

  method part (App::Alice::Window $window, $?) {
    if ($window->is_channel) {
      $window->part;
    }
  }

  method close (App::Alice::Window $window, $?) {
    if ($window->is_channel) {
      $window->part;
    }
    else {
      $self->app->close_window($window);
    }
  }

  method create (App::Alice::Window $window, Str $arg) {
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    my $new_window = $self->app->find_or_create_window($arg, $window->connection);
    $self->app->send($new_window->join_action);
  }

  method clear (App::Alice::Window $window, $?) {
    $window->msgbuffer([]);
    $self->app->send($window->clear_action);
  }

  method topic (App::Alice::Window $window, Str $arg?) {
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

  method me (App::Alice::Window $window, Str $arg) {
    $self->app->send($window->render_message($window->nick, "• $arg"));
    $window->connection->yield("ctcp", $window->title, "ACTION $1");
  }

  method quote (App::Alice::Window $window, Str $arg) {
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    $window->connection->yield("quote", $arg);
  }

  method notfound (App::Alice::Window $window, Str $arg) {
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    $self->app->send($window->render_announcement("Invalid command $arg"));
  }

  method _say (App::Alice::Window $window, Str $arg) {
    $self->app->send($window->render_message($window->nick, $arg));
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    $window->connection->yield("privmsg", $window->title, $arg);
  }
}
