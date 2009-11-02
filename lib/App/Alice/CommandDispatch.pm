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
        {method => 'query',    re => qr{^/query\s+(\S+)}},
        {method => 'names',    re => qr{^/n(?:ames)?\s*$}, in_channel => 1},
        {method => '_join',    re => qr{^/j(?:oin)?\s+(?:-(\S+)\s+)?(\S+)}},
        {method => 'part',     re => qr{^/part}, in_channel => 1},
        {method => 'create',   re => qr{^/create (\S+)}},
        {method => 'close',    re => qr{^/(?:close|wc)}},
        {method => 'clear',    re => qr{^/clear}},
        {method => 'topic',    re => qr{^/topic(?:\s+(.+))?}, in_channel => 1},
        {method => 'whois',    re => qr{^/whois\s+(\S+)}},
        {method => 'me',       re => qr{^/me (.+)}},
        {method => 'nick',     re => qr{^/nick\s+(\S+)}},
        {method => 'quote',    re => qr{^/(?:quote|raw) (.+)}},
        {method => 'notfound', re => qr{^/(.+)(?:\s.*)?}},
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

  method handle (Str $command, App::Alice::Window $window) {
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
          my $method = $handler->{method};
          if ($self->meta->find_method_by_name($method)) {
            $self->$method($window, @args);
          }
          else {
            $self->app->send($self->app->log_info(
              "Error handling $command: $method method not found"));
          }
        }
        return;
      }
    }
  }

  method names (App::Alice::Window $window) {
    $self->app->send([$window->render_announcement($window->nick_table)]);
  }

  method whois (App::Alice::Window $window, Str $arg) {
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    $self->app->send([$window->render_announcement($window->whois_table($arg))]);
  }

  method query (App::Alice::Window $window, Str $arg) {
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    my $new_window = $self->app->find_or_create_window($arg, $window->connection);
    $self->app->send([$new_window->join_action]);
  }

  method _join (App::Alice::Window $window, Str $arg1, Str $arg2?) {
    if ($arg2 and $self->app->ircs->{$arg2}) {
      $window = $self->app->ircs->{$arg2};
    }
    if ($arg1 =~ /^[#&]/) {
      $arg1 = decode("utf8", $arg1, Encode::FB_WARN);
      $window->connection->yield("join", $arg1);
    }
  }

  method part (App::Alice::Window $window) {
    $window->part if $window->is_channel;
  }

  method close (App::Alice::Window $window) {
    $window->is_channel ?
      $window->part : $self->app->close_window($window);
  }
  
  method nick (App::Alice::Window $window, Str $arg) {
    $window->connection->yield(nick => $arg);
  }

  method create (App::Alice::Window $window, Str $arg) {
    return unless $window->connection;
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    my $new_window = $self->app->find_or_create_window($arg, $window->connection);
    $self->app->send([$new_window->join_action]);
  }

  method clear (App::Alice::Window $window) {
    $window->clear_buffer;
    $self->app->send([$window->clear_action]);
  }

  method topic (App::Alice::Window $window, Str $arg?) {
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

  method me (App::Alice::Window $window, Str $arg) {
    $self->app->send([$window->render_message($window->nick, "• $arg")], 1);
    $window->connection->yield("ctcp", $window->title, "ACTION $1");
  }

  method quote (App::Alice::Window $window, Str $arg) {
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    $window->connection->yield("quote", $arg);
  }

  method notfound (App::Alice::Window $window, Str $arg) {
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    $self->app->send([$window->render_announcement("Invalid command $arg")]);
  }

  method _say (App::Alice::Window $window, Str $arg) {
    $self->app->send([$window->render_message($window->nick, $arg)], 1);
    $arg = decode("utf8", $arg, Encode::FB_WARN);
    $window->connection->yield("privmsg", $window->title, $arg);
  }
}
