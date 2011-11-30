package Alice;

use AnyEvent;
use AnyEvent::Strict;
use AnyEvent::Log;

use Any::Moose;
use Text::MicroTemplate::File;
use Digest::MD5 qw/md5_hex/;
use List::Util qw/first/;
use List::MoreUtils qw/any uniq/;
use AnyEvent::IRC::Util qw/filter_colors/;
use IRC::Formatting::HTML qw/html_to_irc/;
use Encode;

use Alice::Window;
use Alice::InfoWindow;
use Alice::HTTP::Server;
use Alice::IRC;
use Alice::Config;
use Alice::Tabset;
use Alice::Request;
use Alice::MessageBuffer;
use Alice::MessageStore;

our $VERSION = '0.20';

with 'Alice::Role::Commands';
with 'Alice::Role::IRCEvents';

has config => (
  is       => 'rw',
  isa      => 'Alice::Config',
);

has _ircs => (
  is      => 'rw',
  isa     => 'ArrayRef',
  default => sub {[]},
);

sub ircs {@{$_[0]->_ircs}}
sub add_irc {push @{$_[0]->_ircs}, $_[1]}
sub has_irc {$_[0]->get_irc($_[1])}
sub get_irc {first {$_->name eq $_[1]} $_[0]->ircs}
sub remove_irc {$_[0]->_ircs([ grep { $_->name ne $_[1] } $_[0]->ircs])}
sub irc_names {map {$_->name} $_[0]->ircs}
sub connected_ircs {grep {$_->is_connected} $_[0]->ircs}

has streams => (
  is      => 'rw',
  isa     => 'ArrayRef',
  default => sub {[]},
);

sub add_stream {unshift @{shift->streams}, @_}
sub no_streams {@{$_[0]->streams} == 0}
sub stream_count {scalar @{$_[0]->streams}}

has message_store => (
  is      => 'ro',
  lazy    => 1,
  default => sub {
    my $self = shift;
    my $buffer = $self->config->path."/buffer.db";
    if (! -e  $buffer) {
      require File::Copy;
      File::Copy::copy($self->config->assetdir."/buffer.db", $buffer);
    }
    Alice::MessageStore->new(dsn => ["dbi:SQLite:dbname=$buffer", "", ""]);
  }
);

has _windows => (
  is        => 'rw',
  isa       => 'ArrayRef',
  default   => sub {[]},
);

sub windows {@{$_[0]->_windows}}
sub add_window {push @{$_[0]->_windows}, $_[1]}
sub has_window {$_[0]->get_window($_[1])}
sub get_window {first {$_->id eq $_[1]} $_[0]->windows}
sub remove_window {$_[0]->_windows([grep {$_->id ne $_[1]} $_[0]->windows])}
sub window_ids {map {$_->id} $_[0]->windows}

has 'template' => (
  is => 'ro',
  isa => 'Text::MicroTemplate::File',
  lazy => 1,
  default => sub {
    my $self = shift;
    Text::MicroTemplate::File->new(
      include_path => $self->config->assetdir . '/templates',
      cache        => 2,
    );
  },
);

has 'info_window' => (
  is => 'ro',
  isa => 'Alice::InfoWindow',
  lazy => 1,
  default => sub {
    my $self = shift;
    my $id = $self->_build_window_id("info", "info");
    my $info = Alice::InfoWindow->new(
      id       => $id,
      buffer   => $self->_build_window_buffer($id),
      render   => sub { $self->render(@_) }
    );
    $self->add_window($info);
    return $info;
  }
);

has 'user' => (
  is => 'ro',
  default => $ENV{USER}
);

sub BUILDARGS {
  my ($class, %options) = @_;

  my $self = {};

  for (qw/template user message_store/) {
    if (exists $options{$_}) {
      $self->{$_} = $options{$_};
      delete $options{$_};
    }
  }

  $self->{config} = Alice::Config->new(
    %options,
    callback => sub {$self->{config}->merge(\%options)}
  );

  return $self;
}

sub run {
  my $self = shift;

  # wait for config to finish loading
  my $w; $w = AE::idle sub {
    return unless $self->config->{loaded};
    undef $w;
    $self->init;
  };
}

sub init {
  my $self = shift;
  $self->info_window;
  $self->template;

  $self->add_irc_server($_, $self->config->servers->{$_})
    for keys %{$self->config->servers};
}

sub init_shutdown {
  my ($self, $cb, $msg) = @_;

  $self->alert("Alice server is shutting down");
  $self->disconnect_irc($_->name, $msg) for $self->connected_ircs;

  my ($w, $t);
  my $shutdown = sub {
    undef $w;
    undef $t;
    $self->shutdown;
    $cb->() if $cb;
  };

  $w = AE::idle sub {$shutdown->() unless $self->connected_ircs};
  $t = AE::timer 3, 0, $shutdown;
}

sub shutdown {
  my $self = shift;

  $self->_ircs([]);
  $_->close for @{$self->streams};
  $self->streams([]);
}

sub tab_order {
  my ($self, $window_ids) = @_;
  my $order = [];
  for my $count (0 .. scalar @$window_ids - 1) {
    if (my $window = $self->get_window($window_ids->[$count])) {
      next unless $window->is_channel;
      push @$order, $window->id;
    }
  }
  $self->config->order($order);
  $self->config->write;
}

sub window_nicks {
  my ($self, $window) = @_;
  return () if $window->type eq "info";

  my $irc = $self->get_irc($window->network);
  if ($irc and $irc->is_connected) {
    if ($window->type eq "channel") {
      return $irc->channel_nicks($window->title);
    }
    else {
      return ($irc->nick, $window->title);
    }
  }
}

sub connect_actions {
  my $self = shift;
  map {
    $_->join_action,
    $_->nicks_action($self->window_nicks($_))
  } $self->windows;
}

sub find_window {
  my ($self, $title, $irc) = @_;
  return $self->info_window if $title eq "info";
  my $id = $self->_build_window_id($title, $irc->name);
  if (my $window = $self->get_window($id)) {
    return $window;
  }
}

sub alert {
  my ($self, $message) = @_;
  return unless $message;
  $self->broadcast({
    type => "action",
    event => "alert",
    body => $message,
  });
}

sub create_window {
  my ($self, $title, $irc) = @_;
  my $id = $self->_build_window_id($title, $irc->name);
  my $window = Alice::Window->new(
    title    => $title,
    type     => $irc->is_channel($title) ? "channel" : "privmsg",
    network  => $irc->name,
    id       => $id,
    buffer   => $self->_build_window_buffer($id),
    render   => sub { $self->render(@_) },
  );
  if ($window->is_channel) {
    my $config = $self->config->servers->{$window->network};
    $config->{channels} = [uniq $title, @{$config->{channels}}];
    $self->config->write;
  }
  $self->add_window($window);
  return $window;
}

sub _build_window_buffer {
  my ($self, $id) = @_;
  Alice::MessageBuffer->new(
    id => $id,
    store => $self->message_store,
  );
}

sub _build_window_id {
  my ($self, $title, $network) = @_;
  md5_hex(encode_utf8(lc $self->user."-$title-$network"));
}

sub find_or_create_window {
  my ($self, $title, $irc) = @_;
  return $self->info_window if $title eq "info";

  if (my $window = $self->find_window($title, $irc)) {
    return $window;
  }

  $self->create_window($title, $irc);
}

sub sorted_windows {
  my $self = shift;

  my %o = map {
    $self->config->order->[$_] => sprintf "%02d", $_ + 2
  } (0 .. @{$self->config->order} - 1);

  $o{$self->info_window->id} = "01";
  my $prefix = scalar @{$self->config->order} + 1;

  map  {$_->[1]}
  sort {$a->[0] cmp $b->[0]}
  map  {[($o{$_->id} || $o{$_->title} || $prefix.$_->sort_name), $_]}
       $self->windows;
}

sub close_window {
  my ($self, $window) = @_;

  AE::log debug => "sending a request to close a tab: " . $window->title;
  $self->broadcast($window->close_action);

  if ($window->is_channel) {
    my $irc = $self->get_irc($window->network);
    my $config = $self->config->servers->{$window->network};
    $config->{channels} = [grep {$_ ne $window->title} @{$config->{channels}}];
    $self->config->write;
  }

  $self->remove_window($window->id) if $window->type ne "info";
}

sub add_irc_server {
  my ($self, $name, $config) = @_;
  $self->config->servers->{$name} = $config;
  my $irc = Alice::IRC->new(name => $name);
  $self->add_irc($irc);
  $self->connect_irc($name) if $config->{autoconnect};
}

sub reload_config {
  my ($self, $new_config) = @_;

  my %prev = map {$_ => $self->config->servers->{$_}{ircname} || ""}
             keys %{ $self->config->servers };

  if ($new_config) {
    $self->config->merge($new_config);
    $self->config->write;
  }
  
  for my $network (keys %{$self->config->servers}) {
    my $config = $self->config->servers->{$network};
    if (!$self->has_irc($network)) {
      $self->add_irc_server($network, $config);
    }
    else {
      my $irc = $self->get_irc($network);
      $config->{ircname} ||= "";
      if ($config->{ircname} ne $prev{$network}) {
        $irc->update_realname($config->{ircname});
      }
    }
  }
  for my $irc ($self->ircs) {
    my $name = $irc->name;
    unless (exists $self->config->servers->{$name}) {
      $self->send_info("config", "removing $name server");
      if ($irc->is_disconnected) {
        $self->cancel_reconnect($name) if $irc->reconnect_timer;
        $irc->cl(undef);
        $self->remove_irc($name);
      }
      else {
        $irc->removed(1);
        $self->disconnect_irc($name);
      }
    }
  }
}

sub announce {
  my ($self, $window, $body) = @_;
  $self->broadcast({
    type => "action",
    event => "announce",
    body => $body
  });
}

sub send_message {
  my ($self, $window, $nick, $body) = @_;

  my $irc = $self->get_irc($window->network);
  my @messages = $window->format_message($nick, $body,
    monospaced => $self->is_monospace_nick($nick),
    self => $irc->nick eq $nick,
    avatar => $irc->nick_avatar($nick) || "",
    highlight => $self->is_highlight($irc->nick, $body),
  );

  if ($messages[0]->{highlight}) {
    push @messages, $self->info_window->format_message(
      $nick, $body, self => 1, source => $nick);
  }

  $self->broadcast(@messages);
}

sub send_info {
  my ($self, $network, $body, %options) = @_;
  return unless $body;
  my $message = $self->info_window->format_message($network, $body, %options);
  $self->broadcast($message);
}

sub broadcast {
  my ($self, @messages) = @_;
  return if $self->no_streams or !@messages;
  for my $stream (@{$self->streams}) {
    $stream->send(\@messages);
  }
}

sub ping {
  my $self = shift;
  return if $self->no_streams;
  $_->ping for grep {$_->is_xhr} @{$self->streams};
}

sub update_window {
  my ($self, $stream, $window, $max, $min, $limit, $total, $cb) = @_;

  my $step = 20;
  if ($limit - $total <  20) {
    $step = $limit - $total;
  }

  $window->buffer->messages($max, $min, $step, sub {
    my $msgs = shift;

    $stream->send([{
      window => $window->serialized,
      type   => "chunk",
      range  => (@$msgs ? [$msgs->[0]{msgid}, $msgs->[-1]{msgid}] : []),
      html   => join "", map {$_->{html}} @$msgs,
    }]);

    $total += $step;

    if (@$msgs == $step and $total < $limit) {
      $max = $msgs->[0]->{msgid} - 1;
      $self->update_window($stream, $window, $max, $min, $limit, $total, $cb);
    }
    else {
      $cb->() if $cb;
      return;
    }
  });
}

sub handle_message {
  my ($self, $message) = @_;

  if (my $window = $self->get_window($message->{source})) {
    my $stream = first {$_->id eq $message->{stream}} @{$self->streams};
    return unless $stream;

    $message->{msg} = html_to_irc($message->{msg}) if $message->{html};

    for my $line (split /\n/, $message->{msg}) {
      next unless $line;

      my $input = Alice::Request->new(
        window => $window,
        stream => $stream,
        line   => $line,
      );

      $self->irc_command($input);
    }
  }
}

sub purge_disconnects {
  my ($self) = @_;
  AE::log debug => "removing broken streams";
  $self->streams([grep {!$_->closed} @{$self->streams}]);
}

sub render {
  my ($self, $template, @data) = @_;
  $self->template->render_file("$template.html", $self, @data)->as_string;
}

sub is_highlight {
  my ($self, $own_nick, $body) = @_;
  $body = filter_colors $body;
  any {$body =~ /(?:\W|^)\Q$_\E(?:\W|$)/i }
      (@{$self->config->highlights}, $own_nick);
}

sub is_monospace_nick {
  my ($self, $nick) = @_;
  any {$_ eq $nick} @{$self->config->monospace_nicks};
}

sub is_ignore {
  my $self = shift;
  return $self->config->is_ignore(@_);
}

sub add_ignore {
  my $self = shift;
  return $self->config->add_ignore(@_);
}

sub remove_ignore {
  my $self = shift;
  return $self->config->remove_ignore(@_);
}

sub ignores {
  my $self = shift;
  return $self->config->ignores(@_);
}

sub static_url {
  my ($self, $file) = @_;
  return $self->config->static_prefix . $file;
}

sub auth_enabled {
  my $self = shift;

  # cache it
  if (!defined $self->{_auth_enabled}) {
    $self->{_auth_enabled} = ($self->config->auth
              and ref $self->config->auth eq 'HASH'
              and $self->config->auth->{user}
              and $self->config->auth->{pass});
  }

  return $self->{_auth_enabled};
}

sub authenticate {
  my ($self, $user, $pass) = @_;
  $user ||= "";
  $pass ||= "";
  if ($self->auth_enabled) {
    return ($self->config->auth->{user} eq $user
       and $self->config->auth->{pass} eq $pass);
  }
  return 1;
}

sub set_away {
  my ($self, $message) = @_;
  my @args = (defined $message ? (AWAY => $message) : "AWAY");
  $_->send_srv(@args) for $self->connected_ircs;
}

sub tabsets {
  my $self = shift;
  map {
    Alice::Tabset->new(
      name => $_,
      windows => $self->config->tabsets->{$_},
    );
  } sort keys %{$self->config->tabsets};
}

__PACKAGE__->meta->make_immutable;
1;
