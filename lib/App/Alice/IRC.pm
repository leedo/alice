package App::Alice::IRC;

use Encode;
use AnyEvent;
use AnyEvent::IRC::Client;
use Moose;

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

sub BUILD {
  my $self = shift;
  $self->meta->error_class('Moose::Error::Croak');

  $self->app->send(
    [$self->app->log_info($self->alias, "connecting")]
  );

  $self->cl->enable_ssl(1) if $self->config->{ssl};
  $self->cl->reg_cb(
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
  $self->cl->connect(
    $self->config->{host}, $self->config->{port},
    {
      nick     => $self->config->{nick},
      real     => $self->config->{ircname},
      password => $self->config->{password},
      user     => $self->config->{username},
    }
  );
}

sub window {
  my ($self, $title) = @_;
  $title = decode("utf8", $title, Encode::FB_WARN);
  return $self->app->find_or_create_window(
           $title, $self);
}

sub nick {
  my $self = shift;
  return $self->cl->nick;
}

sub _connect {
  my ($self, $cl, $con, $err) = @_;
  if (defined $err) {
    $self->app->send([
      $self->app->log_info($self->alias, "connect error: $err")
    ]);
  }
}

sub registered {
  my $self = shift;
  my @log;
  push @log, $self->app->log_info($self->alias, "connected");
  for (@{$self->config->{on_connect}}) {
    push @log, $self->app->log_info($self->alias, "sending $_");
    $self->cl->send_raw($_);
  }

  for (@{$self->config->{channels}}) {
    push @log, $self->app->log_info($self->alias, "joining $_");
    $self->cl->send_srv("JOIN", $_);
  }
  $self->app->send(\@log);
};

sub disconnected {
  my $self = shift;
  $self->app->send(
    [$self->app->log_info($self->alias, "disconnected")]
  );
};

sub publicmsg {
  my ($self, $cl, $channel, $msg) = @_;
  my $nick = (split '!', $msg->{prefix})[0];
  my $text = $msg->{params}[1];
  my $window = $self->window($channel);
  $self->app->send([$window->render_message($nick, $text)]);
};

sub privatemsg {
  my ($self, $cl, $nick, $msg) = @_;
  my $window = $self->window($nick);
  $self->app->send([$window->render_message($nick, $msg)]);
};

sub ctcp_action {
  my ($self, $cl, $nick, $channel, $msg, $type) = @_;
  my $window = $self->window($channel);
  $self->app->send([$window->render_message($nick, "• $msg")]);
};

sub nick_change {
  my ($self, $cl, $old_nick, $new_nick, $is_self) = @_;
  $self->app->send([
    map { $_->rename_nick($old_nick, $new_nick);
          $_->render_event("nick", $old_nick, $new_nick);
    } $self->app->nick_windows($old_nick)
  ]);
}

sub _join {
  my ($self, $cl, $nick, $channel, $is_self) = @_;
  my $window = $self->window($channel);
  if (!$is_self) {
    $window->add_nick($nick);
    $self->app->send([$window->render_event("joined", $nick)]);
  }
}

sub channel_add {
  my ($self, $cl, $msg, $channel, @nicks) = @_;
  my $window = $self->window($channel);
  $window->add_nicks(@nicks);
}

sub part {
  my ($self, $cl, $nick, $channel, $is_self, $msg) = @_;
  my $window = $self->window($channel);
  if ($is_self) {
    $self->app->close_window($window);
    return;
  }
  $self->app->send([
    $window->render_event("left", $nick, $msg)
  ]);
}

sub channel_remove {
  my ($self, $cl, $msg, $channel, @nicks) = @_;
  my $window = $self->window($channel);
  $window->remove_nicks(@nicks);
}

sub quit {
  my ($self, $cl, $nick, $msg) = @_;
  use Data::Dumper;
  print STDERR Dumper $msg;
  $self->app->send([
    map {$_->render_event("left", $nick, $msg)}
        $self->app->nick_windows($nick)
  ]);
};

sub channel_topic {
  my ($self, $cl, $channel, $topic, $nick) = @_;
  my $window = $self->window($channel);
  $window->topic({string => $topic, author => $nick, time => time});
  $self->app->send([
    $window->render_event("topic", $nick, $topic),
  ]);
};

sub log_debug {
  my $self = shift;
  say STDERR join " ", @_ if $self->config->{debug};
}

__PACKAGE__->meta->make_immutable;
1;
