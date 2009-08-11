package Alice::HTTPD;

use strict;
use warnings;

use Alice::AsyncGet;
use Alice::CommandDispatch;
use Moose;
use bytes;
use Encode;
use MIME::Base64;
use Time::HiRes qw/time/;
use DateTime;
use POE;
use POE::Component::Server::HTTP;
use JSON;
use Template;
use URI::QueryParam;
use IRC::Formatting::HTML;
use YAML qw/DumpFile/;

has 'config' => (
  is  => 'ro',
  isa => 'HashRef',
  required => 1,
  trigger => sub {
    my $self = shift;
    POE::Component::Server::HTTP->new(
      Port            => $self->config->{port},
      PreHandler      => {
        '/'             => sub{$self->check_authentication(@_)},
      },
      ContentHandler  => {
        '/serverconfig' => sub{$self->server_config(@_)},
        '/config'       => sub{$self->send_config(@_)},
        '/save'         => sub{$self->save_config(@_)},
        '/view'         => sub{$self->send_index(@_)},
        '/stream'       => sub{$self->setup_stream(@_)},
        '/favicon.ico'  => sub{$self->not_found(@_)},
        '/say'          => sub{$self->handle_message(@_)},
        '/static/'      => sub{$self->handle_static(@_)},
        '/autocomplete' => sub{$self->handle_autocomplete(@_)},
        '/get/'         => sub{async_fetch($_[1],$_[0]->uri); return RC_WAIT;},
      },
      StreamHandler    => sub{$self->handle_stream(@_)},
    );
    POE::Session->create(
      object_states => [
        $self => {
          _start => 'start_ping',
          ping   => 'ping',
        }
      ],
    );
  },
);

before qw/send_config save_config send_index setup_stream not_found
          handle_message handle_static handle_autocomplete server_config/ => sub {
  $_[1]->header(Connection => 'close');
  $_[2]->header(Connection => 'close');
  $_[2]->streaming(0);
  $_[2]->code(200);
};

has 'irc' => (
  is  => 'rw',
  isa => 'Alice::IRC',
  weak_ref => 1,
);

has 'streams' => (
  is  => 'rw',
  isa => 'ArrayRef[POE::Component::Server::HTTP::Response]',
  default => sub {[]},
);

has 'seperator' => (
  is  => 'ro',
  isa => 'Str',
  default => '--xalicex',
);

has 'commands' => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  default => sub { [qw/join part names topic me query/] },
  lazy => 1,
);

has 'dispatch' => (
  is => 'ro',
  isa => 'Alice::CommandDispatch',
  default => sub {
    Alice::CommandDispatch->new(http => shift);
  }
);

has 'windows' => (
  is => 'rw',
  isa => 'HashRef[Alice::Window]',
  default => sub {{}}
);

has 'msgid' => (
  is => 'rw',
  isa => 'Int',
  default => 1,
);

after 'msgid' => sub {
  my $self = shift;
  $self->{msgid} = $self->{msgid} + 1;
};

sub check_authentication {
  my ($self, $req, $res)  = @_;

  return RC_OK unless ($self->config->{auth}
      and ref $self->config->{auth} eq 'HASH'
      and $self->config->{auth}{username}
      and $self->config->{auth}{password});

  if (my $auth  = $req->header('authorization')) {
    $auth =~ s/^Basic //;
    $auth = decode_base64($auth);
    my ($user,$password)  = split(/:/, $auth);
    if ($self->{config}->{auth}->{username} eq $user &&
        $self->{config}->{auth}->{password} eq $password) {
      return RC_OK;
    }
    else {
      $self->log_debug("auth failed");
    }
  }
  $res->code(401);
  $res->header('WWW-Authenticate' => 'Basic realm="Alice"');
  $res->close();
  return RC_DENY;
}

sub setup_stream {
  my ($self, $req, $res) = @_;
  
  # XHR tries to reconnect again with this header for some reason
  return 200 if defined $req->header('error');
  
  $self->log_debug("opening a streaming http connection");
  $res->streaming(1);
  $res->content_type('multipart/mixed; boundary=xalicex; charset=utf-8');
  $res->{msgs} = [];
  $res->{actions} = [];
  
  # populate the msg queue with any buffered messages that are newer
  # than the provided msgid
  if (defined (my $msgid = $req->uri->query_param('msgid'))) {
    $res->{msgs} = $self->buffered_messages;
  }
  push @{$self->streams}, $res;
  return 200;
}

sub buffered_messages {
  my $self = shift;
  return [ map {@{$_->msgbuffer}} @{$self->windows} ];
}

sub get_window {
  my ($self, $title) = @_;
  return $self->windows->{$title};
}

sub handle_stream {
  my ($self, $req, $res) = @_;
  if ($res->is_error) {
    $self->end_stream($res);
    return;
  }
  if (@{$res->{msgs}} or @{$res->{actions}}) {
    my $output;
    if (! $res->{started}) {
      $res->{started} = 1;
      $output .= $self->seperator."\n";
    }
    $output .= to_json({msgs => $res->{msgs}, actions => $res->{actions}, time => time});
    my $padding = " " x (1024 - bytes::length $output);
    $res->send($output . $padding . "\n" . $self->seperator . "\n");
    if ($res->is_error) {
      $self->end_stream($res);
      return;
    }
    else {
      $res->{msgs} = [];
      $res->{actions} = [];
      $res->continue;
    }
  }
}

sub end_stream {
  my ($self, $res) = @_;
  $self->log_debug("closing a streaming http connection");
  for (0 .. scalar @{$self->streams} - 1) {
    if (! $self->streams->[$_] or ($res and $res == $self->streams->[$_])) {
      splice(@{$self->streams}, $_, 1);
    }
  }
  $res->close;
  $res->continue;
}

sub start_ping {
  $_[KERNEL]->delay(ping => 30);
}

sub ping {
  my $self = $_[OBJECT];
  my $data = {
    type  => "action",
    event => "ping",
  };
  push @{$_->{actions}}, $data for @{$self->streams};
  $_->continue for @{$self->streams};
  $_[KERNEL]->delay(ping => 15);
}

sub handle_message {
  my ($self, $req, $res) = @_;
  my $msg  = $req->uri->query_param('msg');
  my $source = lc $req->uri->query_param('source');
  my $session = $req->uri->query_param('session');
  return 200 unless $session;
  my $irc = $self->irc->connection_from_alias($session);
  return 200 unless $irc;
  $self->dispatch->handle($msg, $source, $irc) if length $msg;
  return 200;
}

sub handle_static {
  my ($self, $req, $res) = @_;
  my $file = $req->uri->path;
  my ($ext) = ($file =~ /[^\.]\.(.+)$/);
  if (-e "data$file") {
    open my $fh, '<', "data$file";
    $self->log_debug("serving static file: $file");
    if ($ext =~ /png|gif|jpg|jpeg/i) {
      $res->content_type("image/$ext"); 
    }
    elsif ($ext =~ /js/) {
      $res->header("Cache-control" => "no-cache");
      $res->content_type("text/javascript");
    }
    elsif ($ext =~ /css/) {
      $res->header("Cache-control" => "no-cache");
      $res->content_type("text/css");
    }
    else {
      $self->not_found($req, $res);
    }
    my @file = <$fh>;
    $res->content(join "", @file);
    return 200;
  }
  $self->not_found($req, $res);
}

sub send_index {
  my ($self, $req, $res) = @_;
  $self->log_debug("serving index");
  $res->content_type('text/html; charset=utf-8');
  my $output = '';
  my $channels = [];
  for my $irc ($self->irc->connections) {
    my $session = $irc->session_alias;
    for my $channel (keys %{$irc->channels}) {
      push @$channels, {
        window => {
          id      => window_id($channel, $session),
          title   => $channel,
          session => $session,
        },
        topic   => $irc->channel_topic($channel),
        server  => $irc,
      }
    }
  }
  $self->tt->process('index.tt', {
    windows   => $channels,
    style     => $self->config->{style} || "default",
  }, \$output) or die $!;
  $res->content($output);
  return 200;
}

sub send_config {
  my ($self, $req, $res) = @_;
  $self->log_debug("serving config");
  $res->header("Cache-control" => "no-cache");
  my $output = '';
  $self->tt->process('config.tt', {
    config      => $self->config,
    connections => [ sort {$a->{alias} cmp $b->{alias}}
                     $self->irc->connections ],
  }, \$output);
  $res->content($output);
  return 200;
}

sub server_config {
  my ($self, $req, $res) = @_;
  $self->log_debug("serving blank server config");
  $res->header("Cache-control" => "no-cache");
  my $name = $req->uri->query_param('name');
  $self->log_debug($name);
  my $config = '';
  $self->tt->process('server_config.tt', {name => $name}, \$config);
  my $listitem = '';
  $self->tt->process('server_listitem.tt', {name => $name}, \$listitem);
  $res->content(to_json({config => $config, listitem => $listitem}));
  return 200;
}

sub save_config {
  my ($self, $req, $res) = @_;
  $self->log_debug("saving config");
  my $new_config = {};
  my $servers;
  for my $name ($req->uri->query_param) {
    next unless $req->uri->query_param($name);
    if ($name =~ /^(.+?)_(.+)/) {
      if ($2 eq "channels" or $2 eq "on_connect") {
        $new_config->{$1}{$2} = [$req->uri->query_param($name)];
      }
      else {
        $new_config->{$1}{$2} = $req->uri->query_param($name);
      }
    }
  }
  use Data::Dumper;
  $self->log_debug(Dumper $new_config);
  for my $newserver (values %$new_config) {
    if (! exists $self->config->{servers}{$newserver->{name}}) {
      $self->irc->add_server($newserver->{name}, $newserver);
    }
    $self->config->{servers}{$newserver->{name}} = $newserver;
  }
  DumpFile($ENV{HOME}.'/.alice.yaml', $self->config);
}

sub not_found {
  my ($self, $req, $res) = @_;
  $self->log_debug("serving 404:", $req->uri->path);
  $res->code(404);
  return 404;
}

sub send_topic {
  my ($self, $who, $channel, $session, $topic, $time) = @_;
  my $nick = ( split /!/, $who)[0];
  $self->display_event($nick, $channel, $session, "topic", $topic, $time);
}

sub display_event {
  my ($self, $nick, $window, $session, $event_type, $msg, $event_time) = @_;

  my $event = {
    type      => "message",
    event     => $event_type,
    nick      => $nick,
    window    => {
      title   => $window,
      id      => window_id($window, $session),
      session => $session,
    },
    message   => $msg,
    msgid     => $self->msgid,
    timestamp => make_timestamp(),
  };

  if ($event_time) {
    my $datetime        = DateTime->from_epoch( epoch  => $event_time );
    $event->{eventtime} = $datetime->strftime('%T, %A %d %B, %Y');
  }

  my $html = '';
  $self->tt->process("event.tt", $event, \$html);
  $event->{full_html} = $html;
  $self->{msgbuffer}{$window} = [] unless exists $self->{msgbuffer}{$window};
  push @{$self->msgbuffer->{$window}}, $event;
  $self->send_data($event);
}

sub display_message {
  my ($self, $nick, $window, $session, $text) = @_;
  my $html = IRC::Formatting::HTML->formatted_string_to_html($text);
  my $mynick = $self->irc->connection_from_alias($session)->nick_name;
  my $msg = {
    type      => "message",
    event     => "say",
    nick      => $nick,
    window    => {
      title   => $window,
      id      => window_id($window, $session),
      session => $session,
    },
    msgid     => $self->msgid,
    self      => $nick eq $mynick,
    html      => $html,
    message   => $text,
    highlight => $text =~ /\b$mynick\b/i || 0,
    timestamp => make_timestamp(),
  };
  $html = '';
  $self->tt->process("message.tt", $msg, \$html);
  $msg->{full_html} = $html;
  $self->{msgbuffer}{$window} = [] unless exists $self->{msgbuffer}{$window};
  push @{$self->msgbuffer->{$window}}, $msg;
  $self->send_data($msg);
}

sub display_announcement {
  my ($self, $window, $session, $str) = @_;
  my $announcement = {
    type    => "message",
    event   => "announce",
    window  => {
      title   => $window,
      id      => window_id($window, $session),
      session => $session,
    },
    message => $str
  };
  my $html = '';
  $self->tt->process("announcement.tt", $announcement, \$html);
  $announcement->{full_html} = $html;
  $self->send_data($announcement);
}

sub has_clients {
  my $self = shift;
  return scalar @{$self->streams};
}

sub create_window {
  my ($self, $title, $session) = @_;
  my $window = Alice::Window->new(
    title => $title,
    session => $session,
  );
  my $action = {
    type      => "action",
    event     => "join",
    window    => {
      title   => $title,
      id      => window_id($title, $session),
      session => $session,
    },
    timestamp => make_timestamp(),
  };

  my $irc = $self->irc->connection_from_alias($session);
  if ($title !~ /^#/ and my $user = $irc->nick_info($title)) {
    $action->{topic}  = {
      Value => $user->{Userhost} . " ($session)"
    };
  }

  my $window_html = '';
  $self->tt->process("window.tt", $action, \$window_html);
  $action->{html}{window} = $window_html;
  my $tab_html = '';
  $self->tt->process("tab.tt", $action, \$tab_html);
  $action->{html}{tab} = $tab_html;
  $self->send_data($action);
  $self->log_debug("sending a request for a new tab: $title ") if $self->has_clients;
}

sub close_window {
  my ($self, $title, $session) = @_;
  $self->send_data({
    type      => "action",
    event     => "part",
    window    => {
      id      => window_id($title, $session),
      title   => $title,
      session => $session,
    },
    timestamp => make_timestamp(),
  });
  delete $self->{msgbuffer}{$title};
  $self->log_debug("sending a request to close a tab: $title") if $self->has_clients;
}

sub send_data {
  my ($self, $data) = @_;
  return unless $self->has_clients;
  for my $res (@{$self->streams}) {
    if ($data->{type} eq "message") {
      push @{$res->{msgs}}, $data;
    }
    elsif ($data->{type} eq "action") {
      push @{$res->{actions}}, $data;
    }
  }
  $_->continue for @{$self->streams};
}

sub show_nicks {
  my ($self, $channel, $session) = @_;
  my $irc = $self->irc->connection_from_alias($session);
  $self->display_announcement($channel, $session, format_nick_table($irc->channel_list($channel)));
}

sub format_nick_table {
  my @nicks = @_;
  return "" unless @nicks;
  my $maxlen = 0;
  for (@nicks) {
    my $length = length $_;
    $maxlen = $length if $length > $maxlen;
  }
  my $cols = int(74  / $maxlen + 2);
  my (@rows, @row);
  for (sort {lc $a cmp lc $b} @nicks) {
    push @row, $_ . " " x ($maxlen - length $_);
    if (@row >= $cols) {
      push @rows, [@row];
      @row = ();
    }
  }
  push @rows, [@row] if @row;
  return join "\n", map {join " ", @$_} @rows;
}

sub window_id {
  my $id = join "_", @_;
  $id =~ s/[#&]/chan_/;
  return lc $id;
}

sub make_timestamp {
  return sprintf("%02d:%02d", (localtime)[2,1])
}

sub log_debug {
  my $self = shift;
  print STDERR join " ", @_, "\n" if $self->config->{debug};
}

sub log_info {
  print STDERR join " ", @_, "\n";
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
