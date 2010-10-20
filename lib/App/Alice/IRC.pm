package App::Alice::IRC;

use AnyEvent;
use AnyEvent::IRC::Client;
use List::Util qw/min first/;
use List::MoreUtils qw/uniq none any/;
use Digest::MD5 qw/md5_hex/;
use Any::Moose;
use utf8;
use Encode;

my $email_re = qr/([^<\s]+@[^\s>]+\.[^\s>]+)/;
my $image_re = qr/(https?:\/\/\S+(?:jpe?g|png|gif))/i;

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
    return $self->config->{nick} || "";
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
  isa       => 'ArrayRef[ArrayRef]',
  default   => sub {[]},
);

sub nicks {@{$_[0]->_nicks}}
sub all_nicks {[map {$_->[0]} @{$_[0]->_nicks}]}
sub add_nick {push @{$_[0]->_nicks}, $_[1]}
sub remove_nick {my $n = lc $_[1]; $_[0]->_nicks([grep {lc $_->[0] ne $n} $_[0]->nicks])}
sub get_nick_info {my $n = lc $_[1]; first {lc $_->[0] eq $n} $_[0]->nicks}
sub includes_nick {my $n = lc $_[1]; any {lc $_->[0] eq $n} $_[0]->nicks}
sub all_nick_info {$_[0]->nicks}
sub clear_nicks {$_[0]->_nicks([])}
sub set_nick_info {$_[0]->remove_nick($_[1]); $_[0]->add_nick($_[2]);}

has whois => (
  is        => 'rw',
  isa       => 'HashRef[CodeRef]',
  default   => sub {{}},
);

sub add_whois {
  my ($self, $nick, $cb) = @_;
  $nick = lc $nick;
  $self->whois->{$nick} = {info => "", cb => $cb};
  $self->send_srv(WHOIS => $nick);
}

sub BUILD {
  my $self = shift;
  $self->cl->enable_ssl if $self->config->{ssl};
  $self->disabled(1) unless $self->config->{autoconnect};
  $self->cl->reg_cb(
    registered     => sub{$self->registered($_)},
    channel_add    => sub{$self->channel_add(@_)},
    channel_remove => sub{$self->multiple_left(@_)},
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
    irc_301        => sub{$self->irc_301(@_)}, # AWAY message
    irc_305        => sub{$self->log_message($_[1])}, # AWAY
    irc_306        => sub{$self->log_message($_[1])}, # not AWAY
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

  # kludge to work around broken MOTDs with an extra \015 in the
  # line ending (e.g. irc.omgwtfhax.net)
  if ($cl->{socket}) {
    $self->{orig_on_read} = $cl->{socket}{on_read};
    $cl->{socket}->on_read(sub {
      my ($hdl) = @_;
      $hdl->push_read (line => qr{\015?\015?\012}, sub {
        $cl->_feed_irc_data ($_[1]);
      });
    });
  }

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

  $self->broadcast(map {
    $_->format_event("reconnect", $self->nick, $self->config->{host}),
  } $self->windows);
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

  # set the client's on read function back to the default
  if ($self->{orig_on_read} and ref $self->{orig_on_read} eq "CODE") {
    $self->cl->{socket}->on_read(delete $self->{orig_on_read});
  }

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
    $_->format_event("disconnect", $self->nick, $self->config->{host})
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
  $msg ||= $self->app->config->quitmsg;

  $self->disabled(1);

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
    my $text = $msg->{params}[1];
    utf8::decode($_) for ($text, $nick);

    return if $self->app->is_ignore($nick);

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
  return unless $msg;
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

sub add_nick_channel {
  my ($self, $nick, $channel) = @_;

  if (my $info = $self->get_nick_info($nick)) {
    $info->[2] = [uniq @{$info->[2]}, $channel];
  }
  else {
    $self->add_nick([$nick, "", [$channel]]);
  }
}

sub remove_nick_channel {
  my ($self, $nick, $channel) = @_;

  if (my $info = $self->get_nick_info($nick)) {
    $info->[2] = [ grep {$_ ne $channel} @{$info->[2]} ];
    $self->remove_nick($nick) unless @{$info->[2]};
  }
}

sub remove_channel {
  my ($self, $channel) = @_;
  for my $info ($self->all_nick_info) {
    $_->[2] = [ grep {$_ ne $channel} @{$_->[2]} ]
  }
}

sub _join {
  my ($self, $cl, $nick, $channel, $is_self) = @_;
  utf8::decode($_) for ($nick, $channel);

  $self->add_nick_channel($nick, $channel);

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

  return unless $self->find_window($channel);

  $self->add_nick_channel($_, $channel) for @nicks;
}

sub part {
  my ($self, $cl, $nick, $channel, $is_self, $msg) = @_;
  utf8::decode($_) for ($channel, $nick, $msg);

  if ($is_self and my $window = $self->find_window($channel)) {
    $self->log(debug => "leaving $channel");
    $self->app->close_window($window);

    $self->remove_channel($channel);
  }
}

sub multiple_left {
  my ($self, $cl, $msg, $channel, @nicks) = @_;
  utf8::decode($_) for ($channel, @nicks);
  
  return if !@nicks or grep {$_ eq $self->nick} @nicks;
  
  if (my $window = $self->find_window($channel)) {
    my $body;
    if ($msg->{command} and $msg->{command} eq "PART") {
      $self->remove_nick_channel($_, $channel) for @nicks;
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
  return
    map {$_->[0]}
    grep {any {$_ eq $channel} @{$_->[2]}}
    $self->all_nick_info;
}

sub nick_channels {
  my ($self, $nick) = @_;
  if (my $info = $self->get_nick_info($nick)) {
    return @{$info->[2]};
  }
  return ();
}

sub nick_windows {
  my ($self, $nick) = @_;
  if (my @channels = $self->nick_channels($nick)) {
    return
      grep {$_}
      map {$self->find_window($_)}
      @channels
  }
  return ();
}

sub irc_301 {
  my ($self, $cl, $msg) = @_;

  my ($from, $awaymsg) = @{$msg->{params}};
  utf8::decode($_) for ($from, $awaymsg);

  if (my $window = $self->find_window($from)) {
    $awaymsg = "$from is away ($awaymsg)";
    $window->reply($awaymsg);
  }
}

sub irc_319 {
  my ($self, $cl, $msg) = @_;

  # ignore the first param if it is our own nick, some servers include it
  shift @{$msg->{params}} if $msg->{params}[0] eq $self->nick;

  my ($nick, $channels) = @{$msg->{params}};
  utf8::decode($_) for ($nick, $channels);

  if (my $whois = $self->whois->{lc $nick}) {
    $whois->{info} .= "\nchannels: $channels";
  }
}

sub irc_311 {
  my ($self, $cl, $msg) = @_;

  # ignore the first param if it is our own nick, some servers include it
  shift @{$msg->{params}} if $msg->{params}[0] eq $self->nick;

  # hector adds an extra nick param or something
  shift @{$msg->{params}} if scalar @{$msg->{params}} > 5;

  my ($nick, $user, $address, undef, $real) = @{$msg->{params}};
  utf8::decode($_) for ($nick, $user, $address, $real);

  if (my $whois = $self->whois->{lc $nick}) {
    $whois->{info} .= "nick: $nick"
                    .  "\nuser: $user"
                    .  "\nreal: $real"
                    .  "\nIP: $address";
  }
}

sub irc_312 {
  my ($self, $cl, $msg) = @_;

  # ignore the first param if it is our own nick, some servers include it
  shift @{$msg->{params}} if $msg->{params}[0] eq $self->nick;

  my ($nick, $server) = @{$msg->{params}};
  utf8::decode($_) for ($nick, $server);

  if (my $whois = $self->whois->{lc $nick}) {
    $whois->{info} .= "\nserver: $server";
  }
}

sub irc_318 {
  my ($self, $cl, $msg) = @_;

  # ignore the first param if it is our own nick, some servers include it
  shift @{$msg->{params}} if $msg->{params}[0] eq $self->nick;

  my $nick = $msg->{params}[0];
  utf8::decode($nick);

  if (my $whois = $self->whois->{lc $nick}) {
    $whois->{cb}->($whois->{info});
    delete $self->whois->{lc $nick};
  }
}

sub irc_352 {
  my ($self, $cl, $msg) = @_;
  
  # ignore the first param if it is our own nick, some servers include it
  shift @{$msg->{params}} if $msg->{params}[0] eq $self->nick;

  my ($channel, undef, undef, undef, $nick, undef, @real) = @{$msg->{params}};
  my $real = join "", @real;
  $real =~ s/^[0-9*] //;
  utf8::decode($_) for ($channel, $nick, $real);

  my $info = [$nick, $real, [$channel]];
  
  if (my $prev_info = $self->get_nick_info($nick)) {
    $info->[2] = [ uniq @{$prev_info->[2]}, $channel ];

    if ($real ne $prev_info->[1]) {
      for (grep {$_->previous_nick eq $nick} $self->windows) {
        $_->reset_previous_nick;
      }
    }
  }

  $info->[4] = $self->realname_avatar($real);
  
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
  
  if ($self->whois->{$msg->{params}[1]}) {
    $self->whois->{$msg->{params}[1]}{cb}->();
    delete $self->whois->{$msg->{params}[1]};
  }
}

sub rename_nick {
  my ($self, $nick, $new_nick) = @_;
  if (my $info = $self->get_nick_info($nick)) {
    $info->[0] = $new_nick;
  }
}

sub remove_nicks {
  my ($self, @nicks) = @_;
  return unless @nicks;

  $self->_nicks([
    grep {my $n = $_->[0]; none {$n eq $_} @nicks} $self->nicks
  ]);
}

sub nick_avatar {
  my ($self, $nick) = @_;
  if (my $info = $self->get_nick_info($nick)) {
    return $info->[4];
  }
}

sub realname_avatar {
  my ($self, $realname) = @_;

  if ($realname =~ $email_re) {
    my $email = $1;
    return "http://www.gravatar.com/avatar/"
           . md5_hex($email) . "?s=32&amp;r=x";
  }
  elsif ($realname =~ $image_re) {
    return $1;
  }

  return ();
}

sub update_realname {
  my ($self, $realname) = @_;
  my $nick = $self->nick_cached;
  $self->send_srv(REALNAME => $realname);

  if (my $info = $self->get_nick_info($nick)) { 
    $info->[1] = $realname;
    $info->[4] = $self->realname_avatar($realname);
  }

  for (grep {$_->previous_nick eq $nick} $self->windows) {
    $_->reset_previous_nick;
  }
}

sub is_channel {
  my ($self, $channel) = @_;
  return $self->cl->is_channel_name($channel);
}

__PACKAGE__->meta->make_immutable;
1;

=pod

=head1 NAME

App::Alice::IRC - an Altogether Lovely Internet Chatting Experience

=head2 METHODS

=over 4

=item $irc->connect

Connect to the server. This will not force a reconnect if already
connected.


=item $irc->disconnect

=item $irc->disconnect ($quitmsg)

Sends QUIT with an optional $quitmsg to the server and disconnects.


=item $irc->reconnect
=item $irc->reconnect ($seconds)

Reconnects to the IRC server with an optional $second delay. It will
continue attempting to reconnect until it succeeds, increasing the
delay by 15 seconds each time (maxing out at 5 minutes).


=item $irc->alias

A short name used to describe this server.


=item $irc->is_connected

Returns true if connected to the server.


=item $irc->get_nick_info ($nick)

Get WHOIS related information about $nick.


=item $irc->send_srv ($cmd, @params)

Send the command to the server and format any parameters.


=item $irc->send_raw ($line)

Send the $line as-is to the server.


=item $irc->log ($text, %options)

=item $irc->log ([$text, $text, ... $text], %options)

Takes one or more lines to log and an options hash. This lines
will be sent to the client and printed in the "info" tab.


=item $irc->window ($title)

Returns an App::Alice::Window for this server using $title.
If one already exists it will be returned, otherwise a new
Window will be created.


=item $irc->find_window ($title)

Find an App::Alice::Window from this server by $title.


=item $irc->nick

The nick being used on this server.


=item $irc->windows

Returns a list of App::Alice::Windows for this server.


=item $irc->channels

Returns a list of channel names currently joined for this server.


=item $irc->is_channel ($channelname)

This will return a true value if $channelname is a valid channel name
on this server (e.g. starts with #). This uses the CHANTYPES list
provided by the server's ISUPPORT line.


=item $irc->channel_nicks  ($channelname)

Returns a list of nicks that are in the given $channelname.


=item $irc->nick_channels ($nick)

Returns a list of channel names that $nick is in.


=item $irc->nick_windows ($nick)

Returns a list of App::Alice::Windows that $nick is in.


=item $irc->nick_avatar ($nick)

Returns the avatar (image URL) for $nick, or undef if there is no avatar. 


=item $irc->update_realname ($new_realname)

Update this connection's REALNAME, which will tchange your avatar
for other alice users. Sends a REALNAME command to the server.
This command is only understood by the hector IRC server, and
will be ignored by others.

=back

=cut
