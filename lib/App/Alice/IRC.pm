package App::Alice::IRC;

use AnyEvent;
use AnyEvent::IRC::Client;
use List::Util qw/min first/;
use List::MoreUtils qw/uniq none any/;
use Digest::MD5 qw/md5_hex/;
use Any::Moose;
use utf8;
use Encode;

has 'cl' => (
  is      => 'rw',
  default => sub {AnyEvent::IRC::Client->new},
);

has 'alias' => (
  isa      => 'Str',
  is       => 'ro',
  required => 1,
);

has 'nick_cached' => (
  isa      => 'Str',
  is       => 'rw',
  lazy     => 1,
  default  => sub {
    my $self = shift;
    return $self->config->{nick};
  },
);

sub config {
  $_[0]->app->config->servers->{$_[0]->alias};
}

has 'app' => (
  isa      => 'App::Alice',
  is       => 'ro',
  weak_ref => 1,
  required => 1,
);

has 'reconnect_timer' => (
  is => 'rw'
);

has [qw/reconnect_count connect_time/] => (
  is  => 'rw',
  isa => 'Int',
  default   => 0,
);

sub increase_reconnect_count {$_[0]->reconnect_count($_[0]->reconnect_count + 1)}
sub reset_reconnect_count {$_[0]->reconnect_count(0)}

has [qw/is_connected disabled removed/] => (
  is  => 'rw',
  isa => 'Bool',
  default => 0,
);

has _nicks => (
  is        => 'rw',
  isa       => 'ArrayRef[HashRef|Undef]',
  default   => sub {[]},
);

sub nicks {@{$_[0]->_nicks}}
sub all_nicks {[map {$_->{nick}} @{$_[0]->_nicks}]}
sub add_nick {push @{$_[0]->_nicks}, $_[1]}
sub remove_nick {$_[0]->_nicks([grep {$_->{nick} ne $_[1]} $_[0]->nicks])}
sub get_nick_info {first {$_->{nick} eq $_[1]} $_[0]->nicks}
sub includes_nick {any {$_->{nick} eq $_[1]} $_[0]->nicks}
sub all_nick_info {$_[0]->nicks}
sub set_nick_info {$_[0]->remove_nick($_[1]); $_[0]->add_nick($_[2]);}
sub clear_nicks {$_[0]->_nicks([])}

has whois_cbs => (
  is        => 'rw',
  isa       => 'HashRef[CodeRef]',
  default   => sub {{}},
);

sub add_whois_cb {
  my ($self, $nick, $cb) = @_;
  $self->whois_cbs->{$nick} = $cb;
  $self->send_srv(WHOIS => $nick);
}

sub BUILD {
  my $self = shift;
  $self->cl->enable_ssl if $self->config->{ssl};
  $self->disabled(1) unless $self->config->{autoconnect};
  $self->cl->reg_cb(
    registered     => sub{$self->registered($_)},
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
    disconnect     => sub{$self->disconnected(@_)},
    irc_001        => sub{$self->log_message($_[1])},
    irc_352        => sub{$self->irc_352(@_)}, # WHO info
    irc_311        => sub{$self->irc_311(@_)}, # WHOIS info
    irc_312        => sub{$self->irc_312(@_)}, # WHOIS server
    irc_319        => sub{$self->irc_319(@_)}, # WHOIS channels
    irc_318        => sub{$self->irc_318(@_)}, # end of WHOIS
    irc_366        => sub{$self->irc_366(@_)}, # end of NAMES
    irc_372        => sub{$self->log_message(mono => 1, $_[1])}, # MOTD info
    irc_377        => sub{$self->log_message(mono => 1, $_[1])}, # MOTD info
    irc_378        => sub{$self->log_message(mono => 1, $_[1])}, # MOTD info
    irc_401        => sub{$self->irc_401(@_)}, # not a nick
    irc_471        => sub{$self->log_message($_[1])}, # JOIN fail
    irc_473        => sub{$self->log_message($_[1])}, # JOIN fail
    irc_474        => sub{$self->log_message($_[1])}, # JOIN fail
    irc_475        => sub{$self->log_message($_[1])}, # JOIN fail
    irc_477        => sub{$self->log_message($_[1])}, # JOIN fail
    irc_485        => sub{$self->log_message($_[1])}, # JOIN fail
    irc_432        => sub{$self->nick; $self->log_message($_[1])}, # Bad nick
    irc_433        => sub{$self->nick; $self->log_message($_[1])}, # Bad nick
    irc_464        => sub{$self->disconnect("bad USER/PASS")},
  );
  $self->cl->ctcp_auto_reply ('VERSION', ['VERSION', "alice $App::Alice::VERSION"]);
  $self->connect unless $self->disabled;
}

sub send_srv {
  my ($self, $cmd, @params) = @_;
  $self->cl->send_srv($cmd => map {encode_utf8($_)} @params);
}

sub send_raw {
  my ($self, $cmd) = @_;
  $self->cl->send_raw(encode_utf8($cmd));
}

sub broadcast {
  my $self = shift;
  $self->app->broadcast(@_);
}

sub init_shutdown {
  my ($self, $msg) = @_;
  $self->disabled(1);
  if ($self->is_connected) {
    $self->disconnect($msg);
    return;
  }
  $self->shutdown;
}

sub shutdown {
  my $self = shift;
  $self->cl(undef);
  $self->app->remove_irc($self->alias);
  $self->app->shutdown if !$self->app->ircs;
}

sub log {
  my $messages = pop;
  $messages = [ $messages ] unless ref $messages eq "ARRAY";

  my ($self, $level, %options) = @_;

  my @lines = map {$self->format_info($_, %options)} @$messages;
  $self->broadcast(@lines);
  $self->app->log($level => "[".$self->alias . "] $_") for @$messages;
}

sub log_message {
  my $message = pop;

  my ($self, %options) = @_;
  if (@{$message->{params}}) {
    $self->log("debug", %options, [ pop @{$message->{params}} ]);
  }
}

sub format_info {
  my ($self, $message, %options) = @_;
  $self->app->format_info($self->alias, $message, %options);
}

sub window {
  my ($self, $title) = @_;
  return $self->app->find_or_create_window($title, $self);
}

sub find_window {
  my ($self, $title) = @_;
  return $self->app->find_window($title, $self);
}

sub nick {
  my $self = shift;
  my $nick = $self->cl->nick;
  if ($nick and $nick ne "") {
    $self->nick_cached($nick);
    return $nick;
  }
  return $self->nick_cached || "Failure";
}

sub windows {
  my $self = shift;
  return grep
    {$_->type ne "info" && $_->irc->alias eq $self->alias}
    $self->app->windows;
}

sub channels {
  my $self = shift;
  return map {$_->title} grep {$_->is_channel} $self->windows;
}

sub connect {
  my $self = shift;

  $self->disabled(0);
  $self->increase_reconnect_count;

  $self->cl->{enable_ssl} = $self->config->{ssl} ? 1 : 0;

  # some people don't set these, wtf
  if (!$self->config->{host} or !$self->config->{port}) {
    $self->log(info => "can't connect: missing either host or port");
    return;
  }

  $self->reconnect_count > 1 ? 
    $self->log(info => "reconnecting: attempt " . $self->reconnect_count)
  : $self->log(debug => "connecting");

  $self->cl->connect(
    $self->config->{host}, $self->config->{port}
  );
}

sub connected {
  my ($self, $cl, $err) = @_;

  if (defined $err) {
    $self->log(info => "connect error: $err");
    $self->reconnect();
    return;
  }

  $self->log(info => "connected");
  $self->reset_reconnect_count;
  $self->connect_time(time);
  $self->is_connected(1);

  $self->cl->register(
    $self->nick, $self->config->{username},
    $self->config->{ircname}, $self->config->{password}
  );

  $self->broadcast({
    type => "action",
    event => "connect",
    session => $self->alias,
    windows => [map {$_->serialized} $self->windows],
  });
}

sub reconnect {
  my ($self, $time) = @_;

  my $interval = time - $self->connect_time;

  if ($interval < 15) {
    $time = 15 - $interval;
    $self->log(debug => "last attempt was within 15 seconds, delaying $time seconds")
  }

  if (!defined $time) {
    # increase timer by 15 seconds each time, until it hits 5 minutes
    $time = min 60 * 5, 15 * $self->reconnect_count;
  }

  $self->log(debug => "reconnecting in $time seconds");
  $self->reconnect_timer(
    AnyEvent->timer(after => $time, cb => sub {
      $self->connect unless $self->is_connected;
    })
  );
}

sub cancel_reconnect {
  my $self = shift;
  $self->reconnect_timer(undef);
  $self->reset_reconnect_count;
}

sub registered {
  my $self = shift;
  my @log;

  $self->cl->enable_ping (300, sub {
    $self->disconnected("ping timeout");
  });
  
  for (@{$self->config->{on_connect}}) {
    push @log, "sending $_";
    $self->send_raw($_);
  }
  
  # merge auto-joined channel list with existing channels
  my @channels = uniq @{$self->config->{channels}}, $self->channels;
    
  for (@channels) {
    push @log, "joining $_";
    $self->send_srv("JOIN", split /\s+/);
  }
  
  $self->log(debug => \@log);
};

sub disconnected {
  my ($self, $cl, $reason) = @_;
  delete $self->{disconnect_timer} if $self->{disconnect_timer};
  
  $reason = "" unless $reason;
  return if $reason eq "reconnect requested.";
  $self->log(info => "disconnected: $reason");
  
  $self->broadcast(map {
    $_->format_event("disconnect", $self->nick, $reason),
  } $self->windows);
  
  $self->broadcast({
    type => "action",
    event => "disconnect",
    session => $self->alias,
    windows => [map {$_->serialized} $self->windows],
  });
  
  $self->is_connected(0);
  $self->clear_nicks;
  
  if ($self->app->shutting_down and !$self->app->connected_ircs) {
    $self->shutdown;
    return;
  }
  
  $self->reconnect(0) unless $self->disabled;
  
  if ($self->removed) {
    $self->app->remove_irc($self->alias);
    undef $self;
  }
}

sub disconnect {
  my ($self, $msg) = @_;

  $self->disabled(1);
  if (!$self->app->shutting_down) {
    $self->app->remove_window($_) for $self->windows; 
  }

  $msg ||= $self->app->config->quitmsg;
  $self->log(debug => "disconnecting: $msg") if $msg;
  $self->send_srv(QUIT => $msg);
  $self->{disconnect_timer} = AnyEvent->timer(
    after => 1,
    cb => sub {
      delete $self->{disconnect_timer};
      $self->cl->disconnect($msg);
    }
  );
}

sub remove {
  my $self = shift;
  $self->removed(1);
  $self->disconnect;
}

sub publicmsg {
  my ($self, $cl, $channel, $msg) = @_;
  utf8::decode($channel);
  if (my $window = $self->find_window($channel)) {
    my $nick = (split '!', $msg->{prefix})[0];
    return if $self->app->is_ignore($nick);
    my $text = $msg->{params}[1];
    utf8::decode($_) for ($text, $nick);
    $self->app->store(nick => $nick, channel => $channel, body => $text);
    $self->broadcast($window->format_message($nick, $text)); 
  }
}

sub privatemsg {
  my ($self, $cl, $nick, $msg) = @_;
  my $text = $msg->{params}[1];
  utf8::decode($_) for ($nick, $text);
  if ($msg->{command} eq "PRIVMSG") {
    my $from = (split /!/, $msg->{prefix})[0];
    utf8::decode($from);
    return if $self->app->is_ignore($from);
    my $window = $self->window($from);
    $self->app->store(nick => $from, channel => $from, body => $text);
    $self->broadcast($window->format_message($from, $text)); 
    $self->send_srv(WHO => $from) unless $self->includes_nick($from);
  }
  elsif ($msg->{command} eq "NOTICE") {
    $self->log(debug => $text);
  }
}

sub ctcp_action {
  my ($self, $cl, $nick, $channel, $msg, $type) = @_;
  utf8::decode($_) for ($nick, $msg, $channel);
  return if $self->app->is_ignore($nick);
  if (my $window = $self->find_window($channel)) {
    my $text = "• $msg";
    $self->app->store(nick => $nick, channel => $channel, body => $text);
    $self->broadcast($window->format_message($nick, $text));
  }
}

sub nick_change {
  my ($self, $cl, $old_nick, $new_nick, $is_self) = @_;
  utf8::decode($_) for ($old_nick, $new_nick);
  $self->nick_cached($new_nick) if $is_self;
  $self->rename_nick($old_nick, $new_nick);
  $self->broadcast(
    map  {$_->format_event("nick", $old_nick, $new_nick)}
    $self->nick_windows($new_nick)
  );
}

sub _join {
  my ($self, $cl, $nick, $channel, $is_self) = @_;
  utf8::decode($_) for ($nick, $channel);
  if (!$self->includes_nick($nick)) {
    $self->add_nick({nick => $nick, real => "", channels => {$channel => ''}}); 
  }
  else {
    $self->get_nick_info($nick)->{channels}{$channel} = '';
  }
  if ($is_self) {

    # self->window uses find_or_create, so we don't create
    # duplicate windows here
    my $window = $self->window($channel);

    $self->broadcast($window->join_action);

    # client library only sends WHO if the server doesn't
    # send hostnames with NAMES list (UHNAMES), we to WHO always
    $self->send_srv("WHO" => $channel) if $cl->isupport("UHNAMES");
  }
  elsif (my $window = $self->find_window($channel)) {
    $self->send_srv("WHO" => $nick);
    $self->broadcast($window->format_event("joined", $nick));
  }
}

sub channel_add {
  my ($self, $cl, $msg, $channel, @nicks) = @_;
  utf8::decode($_) for (@nicks, $channel);
  if (my $window = $self->find_window($channel)) {
    for (@nicks) {
      if (!$self->includes_nick($_)) {
        $self->add_nick({nick => $_, real => "", channels => {$channel => ''}}); 
      }
      else {
        $self->get_nick_info($_)->{channels}{$channel} = '';
      }
    } 
  }
}

sub part {
  my ($self, $cl, $nick, $channel, $is_self, $msg) = @_;
  utf8::decode($_) for ($channel, $nick, $msg);
  if ($is_self and my $window = $self->find_window($channel)) {
    $self->log(debug => "leaving $channel");
    $self->app->close_window($window);
    for ($self->all_nick_info) {
      delete $_->{channels}{$channel} if exists $_->{channels}{$channel};
    }
  }
}

sub channel_remove {
  my ($self, $cl, $msg, $channel, @nicks) = @_;
  utf8::decode($_) for ($channel, @nicks);
  
  return if !@nicks or grep {$_ eq $self->nick} @nicks;
  
  if (my $window = $self->find_window($channel)) {
    my $body;
    if ($msg->{command} and $msg->{command} eq "PART") {
      for (@nicks) {
        next unless $self->includes_nick($_);
        delete $self->get_nick_info($_)->{channels}{$channel};
        $self->remove_nick($_) unless $self->nick_channels($_);
      }
    }
    else {
      $self->remove_nicks(@nicks);
      $body = $msg->{params}[0];
      utf8::decode($body);
    }
    $self->broadcast(map {$window->format_event("left", $_, $body)} @nicks);
  }
}

sub channel_topic {
  my ($self, $cl, $channel, $topic, $nick) = @_;
  utf8::decode($_) for ($channel, $nick, $topic);
  if (my $window = $self->find_window($channel)) {
    $window->topic({string => $topic, author => $nick, time => time});
    $self->broadcast($window->format_event("topic", $nick, $topic));
  }
}

sub channel_nicks {
  my ($self, $channel) = @_;
  return [ map {$_->{nick}} grep {exists $_->{channels}{$channel}} $self->all_nick_info ];
}

sub nick_channels {
  my ($self, $nick) = @_;
  my $info = $self->get_nick_info($nick);
  return keys %{$info->{channels}} if $info->{channels};
}

sub nick_windows {
  my ($self, $nick) = @_;
  if ($self->nick_channels($nick)) {
    return grep {$_} map {$self->find_window($_)} $self->nick_channels($nick);
  }
  return;
}

sub irc_319 {
  my ($self, $cl, $msg) = @_;

  # ignore the first param if it is our own nick, some servers include it
  shift @{$msg->{params}} if $msg->{params}[0] eq $self->nick;

  my ($nick, $channels) = @{$msg->{params}};
  return unless $channels;
  utf8::decode($_) for ($nick, $channels);

  my $info = $self->get_nick_info($nick) || {nick => $nick, channels => {}};

  for (split " ", $channels) {
    $info->{channels}{$_} = "" unless $info->{channels}{$_};
  }

  $self->set_nick_info($nick, $info);
}

sub irc_311 {
  my ($self, $cl, $msg) = @_;

  # ignore the first param if it is our own nick, some servers include it
  shift @{$msg->{params}} if $msg->{params}[0] eq $self->nick;

  # hector adds an extra nick param or something
  shift @{$msg->{params}} if scalar @{$msg->{params}} > 5;

  my ($nick, $user, $address, undef, $real) = @{$msg->{params}};
  utf8::decode($_) for ($nick, $user, $address, $real);

  my $info = $self->get_nick_info($nick) || {nick => $nick};
  $info->{user} = $user;
  $info->{real} = $real;
  $info->{IP} = $address;

  $self->set_nick_info($nick, $info);
}

sub irc_312 {
  my ($self, $cl, $msg) = @_;

  # ignore the first param if it is our own nick, some servers include it
  shift @{$msg->{params}} if $msg->{params}[0] eq $self->nick;

  my ($nick, $server) = @{$msg->{params}};
  utf8::decode($_) for ($nick, $server);

  my $info = $self->get_nick_info($nick) || {nick => $nick};
  $info->{server} = $server;

  $self->set_nick_info($nick, $info);
}

sub irc_318 {
  my ($self, $cl, $msg) = @_;

  # ignore the first param if it is our own nick, some servers include it
  shift @{$msg->{params}} if $msg->{params}[0] eq $self->nick;

  my $nick = $msg->{params}[0];
  utf8::decode($nick);

  if ($self->whois_cbs->{$nick}) {
    $self->whois_cbs->{$nick}->();
    delete $self->whois_cbs->{$nick};
  }
}

sub irc_352 {
  my ($self, $cl, $msg) = @_;
  
  # ignore the first param if it is our own nick, some servers include it
  shift @{$msg->{params}} if $msg->{params}[0] eq $self->nick;

  my ($channel, $user, $ip, $server, $nick, $flags, @real) = @{$msg->{params}};
  my $real = join "", @real;
  $real =~ s/^[0-9*] //;
  utf8::decode($_) for ($channel, $user, $nick, $real);

  my $info = {
    IP       => $ip     || "",
    user     => $user   || "",
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
    };

    if ($info->{real} ne $prev_info->{real}) {
      for (grep {$_->previous_nick eq $nick} $self->windows) {
        $_->reset_previous_nick;
      }
    }
  }
  
  $self->set_nick_info($nick, $info);
}

sub irc_366 {
  my ($self, $cl, $msg) = @_;
  utf8::decode($msg->{params}[1]);
  if (my $window = $self->find_window($msg->{params}[1])) {
    $self->broadcast($window->nicks_action);
  }
}

sub irc_401 {
  my ($self, $cl, $msg) = @_;
  utf8::decode($msg->{params}[1]);
  if (my $window = $self->find_window($msg->{params}[1])) {
    $self->broadcast($window->format_announcement("No such nick."));
  }
  
  if ($self->whois_cbs->{$msg->{params}[1]}) {
    $self->whois_cbs->{$msg->{params}[1]}->();
    delete $self->whois_cbs->{$msg->{params}[1]};
  }
}

sub rename_nick {
  my ($self, $nick, $new_nick) = @_;
  return unless $self->includes_nick($nick);
  my $info = $self->get_nick_info($nick);
  $info->{nick} = $new_nick;
  $self->set_nick_info($new_nick, $info);
  $self->remove_nick($nick);
}

sub remove_nicks {
  my ($self, @nicks) = @_;
  $self->_nicks([
    grep {my $n = $_->{nick}; none {$n eq $_} @nicks} $self->nicks
  ]);
}

sub nick_avatar {
  my ($self, $nick) = @_;
  my $info = $self->get_nick_info($nick);
  if ($info and $info->{real}) {
    if ($info->{real} =~ /([^<\s]+@[^\s>]+\.[^\s>]+)/) {
      my $email = $1;
      return "http://www.gravatar.com/avatar/"
           . md5_hex($email) . "?s=32&amp;r=x";
    }
    elsif ($info->{real} =~ /(https?:\/\/\S+(?:jpe?g|png|gif))/) {
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

  my $lines = join "\n",
              map {"$_: $info->{$_}"}
              grep {$info->{$_}} qw/nick real user IP server/;

  if (my @channels = keys %{$info->{channels}}) {
    $lines .= "\nchannels: " . join " ", @channels;
  }

  return $lines;
}

sub update_realname {
  my ($self, $realname) = @_;
  my $nick = $self->nick_cached;
  $self->send_srv(REALNAME => $realname);
  if (my $info = $self->get_nick_info($nick)) { 
    $info->{real} = $realname;
  }
  for (grep {$_->previous_nick eq $nick} $self->windows) {
    $_->reset_previous_nick;
  }
}

__PACKAGE__->meta->make_immutable;
1;
