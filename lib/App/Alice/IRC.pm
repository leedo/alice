use MooseX::Declare;

class App::Alice::IRC {
  use feature ':5.10';
  use Encode;
  use AnyEvent;
  use AnyEvent::IRC::Client;

  has 'cl' => (
    is      => 'rw',
    isa     => 'AnyEvent::IRC::Client',
    default => sub {AnyEvent::IRC::Client->new},
  );

  has 'alias' => (
    isa      => 'Str',
    is       => 'ro',
    required => 1,
  );
  
  has 'config' => (
    isa      => 'HashRef',
    is       => 'ro',
    lazy     => 1,
    default  => sub {
      my $self = shift;
      return $self->app->config->{$self->alias};
    },
  );

  has 'app' => (
    isa      => 'App::Alice',
    is       => 'ro',
    required => 1,
  );

  sub START {
    my $self = shift;
    $self->meta->error_class('Moose::Error::Croak');

    $self->app->send(
      [$self->app->log_info($self->alias, "connecting")]
    );

    $self->cl->enable_ssl(1) if $self->config->{ssl};
    $self->con->reg_cb(
      registered     => sub{$self->registered(@_)},
      channel_add    => sub{$self->channel_add(@_)},
      channel_remove => sub{$self->channel_remove(@_)},
      channel_topic  => sub{$self->channel_topic(@_)},
      join           => sub{$self->_join(@_)},
      part           => sub{$self->part(@_)},
      nick_change    => sub{$self->nick_change(@_)},
      ctcp_action    => sub{$self->ctcp_action(@_)},
      quit           => sub{$self->quit(@_)},
      publicmsg      => sub{$self->publicmsg(@_)},
      privatemsg     => sub{$self->privatemsg(@_)},
      connect        => sub{$self->_connect(@_)},
    );
    $self->con->connect(
      $self->config->{host}, $self->config->{port},
      {
        nick     => $self->config->{nick},
        real     => $self->config->{ircname},
        password => $self->config->{password},
        user     => $self->config->{username},
      }
    );
  }

  method window (Str $title){
    $title = decode("utf8", $title, Encode::FB_WARN);
    return $self->app->find_or_create_window(
             $title, $self->con);
  }

  method _connect ($con, $err) {
    if (defined $err) {
      $self->app->send([
        $self->app->log_info($self->alias, "connect error: $err")
      ]);
    }
  }

  method registered {
    my @log;
    push @log, $self->app->log_info($self->alias, "connected");
    for (@{$self->config->{on_connect}}) {
      push @log, $self->app->log_info($self->alias, "sending $_");
      $self->con->send_raw($_);
    }

    for (@{$self->config->{channels}}) {
      push @log, $self->app->log_info($self->alias, "joining $_");
      $self->con->join($_);
    }
    $self->app->send(\@log);
  };
  
  method disconnected {
    $self->app->send(
      [$self->app->log_info($self->alias, "disconnected")]
    );
  };

  method publicmsg ($channel, $msg) {
    my $nick = ( split /!/, $who )[0];
    my $window = $self->window($where->[0]);
    $self->app->send([$window->render_message($nick, $what)]);
  };

  method privatemsg ($nick, $msg) {
    my $window = $self->window($nick);
    $self->app->send([$window->render_message($nick, $what)]);
  };

  method ctcp_action ($nick, $channel, $msg, $type) {
    my $window = $self->window($channel);
    $self->app->send([$window->render_message($nick, "• $msg")]);
  };

  method nick_change ($old_nick, $new_nick, $is_self) {
    $self->app->send([
      map { $_->rename_nick($nick, $new_nick);
            $_->render_event("nick", $nick, $new_nick)
      } $self->app->nick_windows($nick);
    ]);
  }

  method _join ($nick, $channel, $is_self) {
    my $window = $self->window($channel);
    if (!$is_self) {
      $window->add_nick($nick);
      $self->app->send([$window->render_event("joined", $nick)]);
    }
  }

  method channel_add ($msg, $channel, @nicks) {
    my $window = $self->window($channel);
    $window->add_nicks(@nicks);
  }

  method part ($nick, $channel, $is_self, $msg) {
    my $window = $self->window($where);
    if ($is_self) {
      $self->app->close_window($window);
      return;
    }
    $self->app->send([
      $window->render_event("left", $nick, $msg)
    ]);
  }

  method channel_remove ($msg, $channel, @nicks) {
    $window->remove_nicks(@nick);
  }

  method quit ($nick, $msg) {
    $self->app->send([
      map {$_->render_event("left", $nick, $msg)}
          $self->app->nick_windows($nick);
    ]);
  };
  
  method channel_topic ($channel, $topic, $who) {
    my $window = $self->window($channel);
    $self->app->send([
      $window->render_event("topic", $nick, $topic),
    ]);
  };

  sub log_debug {
    my $self = shift;
    say STDERR join " ", @_ if $self->config->{debug};
  }
}
