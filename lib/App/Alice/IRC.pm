package App::Alice::IRC;

use Encode;
use AnyEvent;
use AnyEvent::IRC::Client;
use Digest::MD5 qw/md5_hex/;
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

has nicks => (
  traits    => ['Hash'],
  is        => 'rw',
  isa       => 'HashRef[HashRef|Undef]',
  default   => sub {{}},
  handles   => {
    remove_nick   => 'delete',
    includes_nick => 'exists',
    get_nick_info => 'get',
    all_nicks     => 'keys',
    all_nick_info => 'values',
    set_nick_info => 'set',
  }
);

sub BUILD {
  my $self = shift;
  $self->meta->error_class('Moose::Error::Croak');

  $self->app->send(
    [$self->log_info("connecting")]
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
    publicmsg      => sub{$self->publicmsg(@_)},
    privatemsg     => sub{$self->privatemsg(@_)},
    connect        => sub{$self->connected(@_)},
    irc_352        => sub{$self->irc_352(@_)}, # WHO info
    irc_366        => sub{$self->irc_366(@_)}, # end of NAMES
    irc_372        => sub{$self->log_info(@_)}, # MOTD info
    irc_377        => sub{$self->log_info(@_)}, # MOTD info
    irc_378        => sub{$self->log_info(@_)}, # MOTD info
  );
  $self->connect;
}

sub log_info {
  my ($self, $msg) = @_;
  $self->app->log_info($self->alias, $msg);
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

sub windows {
  my $self = shift;
  return grep {$_->id ne "info" && $_->irc->alias eq $self->alias} $self->app->windows;
}

sub connect {
  my $self = shift;
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

sub connected {
  my ($self, $cl, $con, $err) = @_;
  if (defined $err) {
    $self->app->send([
      $self->log_info("connect error: $err")
    ]);
  }
}

sub registered {
  my $self = shift;
  my @log;
  $self->cl->enable_ping (60, sub {
    $self->log_info("disconnected from server, reconnecting in 10 seconds");
    AnyEvent->timer(after => 10, cb => sub {shift->connect});
  });
  push @log, $self->log_info("connected");
  for (@{$self->config->{on_connect}}) {
    push @log, $self->log_info("sending $_");
    $self->cl->send_raw($_);
  }

  for (@{$self->config->{channels}}) {
    push @log, $self->log_info("joining $_");
    $self->cl->send_srv("JOIN", $_);
  }
  $self->app->send(\@log);
};

sub disconnected {
  my $self = shift;
  $self->app->send(
    [$self->log_info("disconnected")]
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
  $self->app->send([$window->render_message($nick, $msg->{params}[1])]);
};

sub ctcp_action {
  my ($self, $cl, $nick, $channel, $msg, $type) = @_;
  my $window = $self->window($channel);
  $self->app->send([$window->render_message($nick, "• $msg")]);
};

sub nick_change {
  my ($self, $cl, $old_nick, $new_nick, $is_self) = @_;
  $self->rename_nick($old_nick, $new_nick);
  $self->app->send([
    map {$_->render_event("nick", $old_nick, $new_nick)}
        $self->nick_windows($old_nick)
  ]);
}

sub _join {
  my ($self, $cl, $nick, $channel, $is_self) = @_;
  my $window = $self->window($channel);
  if ($is_self) {
    $self->cl->send_srv("WHO $channel");
  }
  else {
    $self->cl->send_srv("WHO $nick");
    if (!$self->includes_nick($nick)) {
      $self->add_nick($nick, {nick => $nick, channels => {$channel => ''}}); 
    }
    else {
      $self->get_nick_info($nick)->{channels}{$channel} = '';
    }
    $self->app->send([$window->render_event("joined", $nick)]);
  }
}

sub channel_add {
  my ($self, $cl, $msg, $channel, @nicks) = @_;
  my $window = $self->window($channel);
  for (@nicks) {
    if (!$self->includes_nick($_)) {
      $self->add_nick($_, {nick => $_, channels => {$channel => ''}}); 
    }
    else {
      $self->get_nick_info($_)->{channels}{$channel} = '';
    }
  }
}

sub part {
  my ($self, $cl, $nick, $channel, $is_self, $msg) = @_;
  if ($is_self) {
    my $window = $self->app->find_window($channel, $self);
    if ($window) {
      $self->app->close_window($window);
    }
  }
}

sub channel_remove {
  my ($self, $cl, $msg, $channel, @nicks) = @_;
  return if grep {$_ eq $self->nick} @nicks;
  my $window = $self->window($channel);
  $self->remove_nicks(@nicks);
  $self->app->send([
    map {$window->render_event("left", $_, $msg->{params}[0])} @nicks
  ]);
}

sub channel_topic {
  my ($self, $cl, $channel, $topic, $nick) = @_;
  my $window = $self->window($channel);
  $window->topic({string => $topic, author => $nick, time => time});
  $self->app->send([$window->render_event("topic", $nick, $topic)]);
}

sub channel_nicks {
  my ($self, $channel) = @_;
  return map {$_->{nick}} grep {exists $_->{channels}{$channel}} $self->all_nick_info;
}

sub nick_channels {
  my ($self, $nick) = @_;
  my $info = $self->get_nick_info($nick);
  return keys %{$info->{channels}} if $info->{channels};
}

sub nick_windows {
  my ($self, $nick) = @_;
  if ($self->nick_channels($nick)) {
    return map {$self->window($_)} $self->nick_channels($nick);
  }
  return;
}

sub irc_352 {
  my ($self, $cl, $msg) = @_;
  my (undef, $channel, $user, $ip, $server, $nick, $flags, $real) = @{$msg->{params}};
  return unless $nick;
  $real =~ s/^\d // if $real;
  my $info = {
    IP       => $ip     || "",
    server   => $server || "",
    real     => $real   || "",
    channels => {$channel => $flags},
    nick     => $nick,
  };
  if ($self->includes_nick($nick)) {
    my $prev_info = $self->get_nick_info($nick);
    $info->{channels} = {
      %{$prev_info->{channels}},
      %{$info->{channels}},
    }
  }  
  $self->set_nick_info($nick, $info);
}

sub irc_366 {
  my ($self, $cl, $msg) = @_;
  my $window = $self->window($msg->{params}[1]);
  $self->app->send([
    $window->join_action,
    $window->nicks_action,
  ]);
}

sub rename_nick {
  my ($self, $nick, $new_nick) = @_;
  return unless $self->includes_nick($nick);
  my $info = $self->get_nick_info($nick);
  $self->set_nick_info($new_nick, $info);
  $self->remove_nick($nick);
}

sub remove_nicks {
  my ($self, @nicks) = @_;
  for (@nicks) {
    $self->remove_nick($_);
  }
}

sub add_nick {
  my ($self, $nick, $data) = @_;
  $self->set_nick_info($nick, $data);
}

sub nick_avatar {
  my ($self, $nick) = @_;
  my $info = $self->get_nick_info($nick);
  if ($info and $info->{real}) {
    if ($info->{real} =~ /.+@.+/) {
      return "//www.gravatar.com/avatar/"
           . md5_hex($info->{real}) . "?s=32&amp;r=x";
    }
    elsif ($info->{real} =~ /^https?:(\/\/\S+(?:jpe?g|png|gif))/) {
      return $1;
    }
    else {
      return undef;
    }
  }
}

sub whois_table {
  my ($self, $nick) = @_;
  my $info = $self->get_nick_info($nick);
  return "No info for user \"$nick\"" if !$info;
  return "real: $info->{real}\nserver: $info->{server}\nchannels: " .
         join " ", keys %{$info->{channels}};
}

sub log_debug {
  my $self = shift;
  say STDERR join " ", @_ if $self->config->{debug};
}

__PACKAGE__->meta->make_immutable;
1;
