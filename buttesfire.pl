#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use lib 'extlib/lib/perl5';
use local::lib 'extlib';
use YAML qw/LoadFile/;
use Template;
use JSON;
use Encode;
use IRC::Formatting;
use Time::HiRes qw/time/;
use URI::QueryParam;
use POE qw/Component::IRC::State Component::IRC::Plugin::Connector
           Component::Server::HTTP/;

$0 = 'buttesfire-web';
system('renice', '+10', $$);
my @open_responses;
my $seperator = "--xbuttesfirex";
my $config = LoadFile($ENV{HOME}.'/.buttesfire.yaml');
my $tt = Template->new(
  INCLUDE_PATH => 'data/templates',
  ENCODING     => 'UTF8');

my $http = POE::Component::Server::HTTP->new(
  Port             => 8080,
  ContentHandler   => {
    '/view'        => \&send_index,
    '/stream'      => \&setup_stream,
    '/favicon.ico' => \&not_found,
    '/say'         => \&handle_message,
    '/static'      => \&handle_static,
  },
  StreamHandler    => \&handle_stream,
);

my $irc = POE::Component::IRC::State->spawn(
  nick    => $config->{nick}    || 'nick',
  ircname => $config->{ircname} || 'nick',
  server  => $config->{server}  || 'irc.freenode.org',
  port    => $config->{port}    || 6667,
  password => $config->{password},
  username => $config->{username},
);

POE::Session->create(
  package_states => [
    main => [qw/_start irc_public irc_001 irc_join irc_part
                irc_quit irc_chan_sync irc_topic irc_ctcp_action
                irc_nick irc_msg/]
  ],
);
$poe_kernel->run;

sub setup_stream {
  my ($req, $res) = @_;
  $res->code(200);
  $res->header(Connection => 'close');
  
  # XHR tries to reconnect again for some reason
  # possibly a problem with multiple browsers viewing
  my $op = $req->header('operation');
  return 200 if $op and $op eq 'read';
  
  log_debug("opening a streaming http connection");
  $res->streaming(1);
  $res->content_type('multipart/mixed; boundary=xbuttesfirex; charset=utf-8');
  $res->{msgs} = [];
  $res->{actions} = [];
  push @open_responses, $res;
  return 200;
}

sub handle_stream {
  my ($req, $res) = @_;

  if ($res->is_error) {
    log_debug("closing HTTP connection");
    for (0 .. $#open_responses) {
      if ($res == $open_responses[$_]) {
        splice(@open_responses, $_, 1);
      }
    }
    $res->close;
    $res->continue;
    return;
  }
  if (@{$res->{actions}} or @{$res->{msgs}}) {
    my $output;
    if (! $res->{started}) {
      $res->{started} = 1;
      $output .= "$seperator\n";
    }
    $output .= to_json({msgs => $res->{msgs}, actions => $res->{actions}, time => time});
    $res->send($output . "\n$seperator\n") if @{$res->{msgs}} or @{$res->{actions}};
    if (! $res->is_error) {
      $res->{msgs} = [];
      $res->{actions} = []; 
    }
  }
  $res->continue;
}

sub handle_message {
  my ($req, $res) = @_;
  $res->streaming(0);
  my $msg  = $req->uri->query_param('msg');
  my $chan = $req->uri->query_param('chan');
  if (length $msg) {
    if ($msg =~ /^\/join (.+)/) {
      $irc->yield( join => $1);
    }
    elsif ($msg =~ /^\/part\s?(.+)?/) {
      $irc->yield( part => $1 || $chan);
    }
    elsif ($msg =~ /^\/n(?:ames)?$/ and $chan) {
      show_nicks($chan);
    }
    elsif ($msg =~ /^\/topic\s?(.+)?/) {
      if ($1) {
        $irc->yield(topic => $chan, $1);
      }
      else {
        my $topic = $irc->channel_topic($chan);
        send_topic($topic->{SetBy}, $chan, $topic->{Value});
      }
    }
    elsif ($msg =~ /^\/me (.+)/) {
      display_message($config->{nick}, $chan, decode_utf8("• $1"));
      $irc->yield(ctcp => $chan, "ACTION $1");
    }
    else {
      log_debug("sending message to $chan");
      display_message($config->{nick}, $chan, decode_utf8($msg)); 
      $irc->yield( privmsg => $chan => $msg);
    }
  }
  $res->code(200);
  return 200;
}

sub handle_static {
  my ($req, $res) = @_;
  $res->streaming(0);
  my $file = $req->uri->query_param("f");
  my ($ext) = ($file =~ /[^\.]\.(.+)$/);
  if (-e "data/static/$file") {
    open my $fh, '<', "data/static/$file";
    log_debug("serving static file: $file");
    if ($ext =~ /png|gif|jpg|jpeg/i) {
      $res->content_type("image/$ext"); 
    }
    elsif ($ext =~ /js/) {
      $res->content_type("text/javascript");
    }
    elsif ($ext =~ /css/) {
      $res->content_type("text/css");
    }
    my @file = <$fh>;
    $res->code(200);
    $res->content(join "", @file);
    return 200;
  }
  not_found($req, $res);
}

sub send_index {
  my ($req, $res) = @_;
  log_debug("server index");
  $res->code(200);
  $res->streaming(0);
  $res->content_type('text/html; charset=utf-8');
  my $output = '';
  $tt->process('index.tt', {
    channels => [ map {
      {name => $_, topic => $irc->channel_topic($_)}
    } keys %{$irc->channels} ]
  }, \$output) or die $!;
  $res->content($output);
  return 200;
}

sub not_found {
  my ($req, $res) = @_;
  log_debug("serving 404:", $req->uri->path);
  $res->streaming(0);
  $res->code(404);
  return 404;
}

sub _start {
  $irc->yield( register => 'all' );
  $irc->plugin_add('Connector' => POE::Component::IRC::Plugin::Connector->new);
  $irc->yield( connect => { } );
  log_info("You can view your IRC session at: http://localhost:8080/view");
  log_debug("connected to irc server");
  return;
}

sub irc_001 {
  log_debug("joining channels");
  for (@{$config->{channels}}) {
    log_debug("joining $_");
    $irc->yield( join => $_ );
  }
}

sub irc_public {
  my ($who, $where, $what) = @_[ARG0 .. ARG2];
  my $nick = ( split /!/, $who )[0];
  my $channel = $where->[0];
  $what = decode("utf8", $what, Encode::FB_WARN);
  display_message($nick, $channel, $what);
}

sub irc_msg {
  my ($who, $what) = @_[ARG0, ARG2];
  my $nick = ( split /!/, $who)[0];
  $what = decode("utf8", $what, Encode::FB_WARN);
  display_message($nick, $nick, $what);
}

sub irc_ctcp_action {
  my ($who, $where, $what) = @_[ARG0 .. ARG2];
  my $nick = ( split /!/, $who )[0];
  my $channel = $where->[0];
  $what = decode("utf8", "• $what", Encode::FB_WARN);
  display_message($nick, $channel, $what);
}

sub irc_nick {
  my ($who, $new_nick) = @_[ARG0, ARG1];
  my $nick = ( split /!/, $who )[0];
  display_event($nick, $_, "is now known as $new_nick")
    for $irc->nick_channels($new_nick);
}

sub irc_join {
  my ($who, $where) = @_[ARG0, ARG1];
  my $nick = ( split /!/, $who)[0];
  my $channel = $where;
  if ($nick ne $config->{nick}) {
    display_event($nick, $channel, "joined");  
  }
  else {
    create_tab($channel);
  }
}

sub irc_chan_sync {
  my ($channel) = @_;
  create_tab($channel) if $channel ne "main";
}

sub irc_part {
  my ($who, $where, $msg) = @_[ARG0 .. ARG2];
  my $nick = ( split /!/, $who)[0];
  my $channel = $where;
  if ($nick ne $config->{nick}) {
    display_event($nick, $channel, "left", $msg);
  }
  else {
    close_tab($channel);
  }
}

sub irc_quit {
  my ($who, $msg, $channels) = @_[ARG0 .. ARG2];
  my $nick = ( split /!/, $who)[0];
  for my $channel (@$channels) {
    display_event($nick, $channel, "left", $msg);
  }
}

sub irc_topic {
  my ($who, $channel, $topic) = @_[ARG0 .. ARG2];
  send_topic($who, $channel, $topic);
}

sub send_topic {
  my ($who, $channel, $topic) = @_;
  my $nick = ( split /!/, $who)[0];
  display_event($nick, $channel, "topic", $topic);
}

sub display_event {
  my ($nick, $channel, $event_type, $msg) = @_;
  my $event = {
    type      => "event",
    nick      => $nick,
    chan      => $channel,
    event     => $event_type,
    message   => $msg,
    timestamp => make_timestamp(),
  };
  add_outgoing($event, "event");
}

sub display_message {
  my ($nick, $channel, $text) = @_;
  my $html = IRC::Formatting->formatted_string_to_html($text);
  my $mynick = $config->{nick};
  my $msg = {
    type      => "message",
    nick      => $nick,
    chan      => $channel,
    self      => $nick eq $config->{nick},
    html      => $html,
    highlight => $text =~ /$mynick/i || 0,
    timestamp => make_timestamp(),
  };
  add_outgoing($msg, "message");
}

sub create_tab {
  my ($name) = @_;
  my $action = {
    type      => "join",
    chan      => $name,
    timestamp => make_timestamp(),
  };
  my $chan_html = '';
  $tt->process("channel.tt", {channel => {name => $name}}, \$chan_html);
  $action->{html}{channel} = $chan_html;
  my $tab_html = '';
  $tt->process("tab.tt", {channel => {name => $name}}, \$tab_html);
  $action->{html}{tab} = $tab_html;
  log_debug("sending a request for a new tab: $name") if @open_responses;
  push @{$_->{actions}}, $action for @open_responses;
}

sub close_tab {
  my ($name) = @_;
  my $action = {
    type      => "part",
    chan      => $name,
    timestamp => make_timestamp(),
  };
  log_debug("sending a request to close a tab: $name") if @open_responses;
  push @{$_->{actions}}, $action for @open_responses;
}

sub add_outgoing {
  my ($hashref, $type) = @_;
  my $html = '';
  $tt->process("$type.tt", $hashref, \$html);
  $hashref->{full_html} = $html;
  log_debug("adding $type to response queues") if @open_responses;
  push @{$_->{msgs}}, $hashref for @open_responses;
}

sub show_nicks {
  my $chan = shift;
  push @{$_->{actions}}, {
    type  => "announce",
    chan  => $chan,
    str   => format_nick_table($irc->channel_list($chan))
  } for @open_responses;
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

sub make_timestamp {
  return sprintf("%02d:%02d", (localtime)[2,1])
}

sub log_debug {
  return unless $config->{debug};
  print STDERR join " ", @_, "\n";
}

sub log_info {
  print STDERR join " ", @_, "\n";
}
