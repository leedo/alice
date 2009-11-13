use MooseX::Declare;

class App::Alice::IRC {
  use feature ':5.10';
  use Encode;
  use AnyEvent;
  use AnyEvent::IRC::Client;

  has 'con' => (
    is      => 'rw',
    isa     => 'AnyEvent::IRC::Client',
    default => sub {AnyEvent::IRC::Client->new},
  );

  has 'c' => (
    is      => 'ro',
    default => sub {AnyEvent->condvar},
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

    $self->con->enable_ssl(1) if $self->config->{ssl};
    $self->con->reg_cb(registered => sub{$self->registered(@_)});
    $self->con->reg_cb(connect => sub{$self->connect(@_)});
    $self->con->connect(
      $self->config->{host}, $self->config->{port},
      {
        nick     => $self->config->{nick},
        real     => $self->config->{ircname},
        password => $self->config->{password},
        user     => $self->config->{username},
      }
    );
    $self->c->wait;  
  }

  method window (Str $title){
    $title = decode("utf8", $title, Encode::FB_WARN);
    return $self->app->find_or_create_window(
             $title, $self->con);
  }

  method connect {
    my ($con, $err) = @_;
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
  
  method quit {
    $self->con->disconnect;
    $self->c->broadcast;
  }

  method disconnected {
    $self->app->send(
      [$self->app->log_info($self->alias, "disconnected")]
    );
  };

  method publicmsg {
    my ($channel, $msg) = @_;
    my $nick = ( split /!/, $who )[0];
    my $window = $self->window($where->[0]);
    $self->app->send([$window->render_message($nick, $what)]);
  };

  method privatemsg {
    my ($nick, $msg) = @_;
    my $window = $self->window($nick);
    $self->app->send([$window->render_message($nick, $what)]);
  };

  method ctcp_action {
    my ($nick, $channel, $msg, $type) = @_;
    my $window = $self->window($channel);
    $self->app->send([$window->render_message($nick, "• $msg")]);
  };

  method nick_change {
    my ($old_nick, $new_nick, $is_self) = @_;
    $self->app->send([
      map { $_->rename_nick($nick, $new_nick);
            $_->render_event("nick", $nick, $new_nick)
      } $self->app->nick_windows($nick)
    ]);
  }

  method _join {
    my ($nick, $channel, $is_self) = @_;
    my $window = $self->window($channel);
    if (!$is_self) {
      $window->add_nick($nick);
      $self->app->send([$window->render_event("joined", $nick)]);
    }
  }

  method channel_add {
    my ($msg, $channel, @nicks) = @_;
    my $window = $self->window($channel);
    $window->add_nicks(@nicks);
  }

  method part {
    my ($nick, $channel, $is_self, $msg) = @_;
    my $window = $self->window($where);
    if ($is_self) {
      $self->app->close_window($window);
      return;
    }
    $self->app->send([
      $window->render_event("left", $nick, $msg)
    ]);
  }

  method channel_remove {
    my ($msg, $channel, @nicks) = @_;
    $window->remove_nicks(@nick);
  }

  method quit {
    my ($nick, $msg) = @_
    # FIXME
    #my @events = map {
    #  my $window = $self->window($_);
    #  $window->remove_nick($nick);
    #  $window->render_event("left", $nick, $msg);
    #} @$channels;
    #$self->app->send(\@events);
  };
  
  method invited {
    # FIXME
    #my ($self, $who, $where) = @_;
    #$self->app->send([
    #  $self->app->log_info($self->alias, "$nick has invited you to join $where"),
    #  $self->app->render_notice("invite", $nick, $where)
    #]);
  };

  method channel_topic {
    my ($channel, $topic, $who) = @_;
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
