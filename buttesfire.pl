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
use bytes;
use POE qw/Component::IRC::State Component::IRC::Plugin::Connector
           Component::Server::HTTP/;

$0 = 'buttesfire-web';
my @open_responses;
my $seperator = "--xbuttesfirex";
my $config = LoadFile($ENV{HOME}.'/.buttesfire.yaml');
my $tt = Template->new(
  INCLUDE_PATH => 'data/templates',
  ENCODING     => 'UTF8');

my @commands = qw/join part names topic me query/;

log_info("You can view your IRC session at: http://localhost:8080/view");

my $http = POE::Component::Server::HTTP->new(
  Port             => 8080,
  ContentHandler   => {
    '/view'        => \&send_index,
    '/stream'      => \&setup_stream,
    '/favicon.ico' => \&not_found,
    '/say'         => \&handle_message,
    '/static'      => \&handle_static,
    '/autocomplete' => \&handle_autocomplete,
  },
  StreamHandler    => \&handle_stream,
);

my %ircs;

for my $server (@{$config->{servers}}) {
  my $irc = POE::Component::IRC::State->spawn(
    nick    => $server->{nick}    || 'nick',
    ircname => $server->{ircname} || 'nick',
    server  => $server->{server}  || 'irc.freenode.org',
    port    => $server->{port}    || 6667,
    password => $server->{password},
    username => $server->{username},
  );
  $ircs{$irc->session_id} = $irc;
  POE::Session->create(
    package_states => [
      main => [qw/_start irc_public irc_001 irc_join irc_part
                  irc_quit irc_chan_sync irc_topic irc_ctcp_action
                  irc_nick irc_msg/]
    ],
    heap => {irc => $irc, network => $server->{server} .":" . $server->{port}},
  );
}

$poe_kernel->run;

sub setup_stream {
  my ($req, $res) = @_;
  $res->code(200);
  $res->header(Connection => 'close');
  
  # XHR tries to reconnect again with this header for some reason
  if (defined $req->header('error')) {
    $res->streaming(0);
    return 200;
  }
  
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
    end_stream($res);
    return;
  }
  if (@{$res->{actions}} or @{$res->{msgs}}) {
    my $output;
    if (! $res->{started}) {
      $res->{started} = 1;
      $output .= "$seperator\n";
    }
    $output .= to_json({msgs => $res->{msgs}, actions => $res->{actions}, time => time});
    my $padding = " " x (1024 - bytes::length $output);
    $res->send($output . $padding . "\n$seperator\n") if @{$res->{msgs}} or @{$res->{actions}};
    if ($res->is_error) {
      end_stream($res);
      return;
    }
    else {
      $res->{msgs} = [];
      $res->{actions} = []; 
    }
  }
  #$res->continue_delayed(0.5);
}

sub end_stream {
  my $res = shift;
  log_debug("closing HTTP connection");
  for (0 .. $#open_responses) {
    if ($res == $open_responses[$_]) {
      splice(@open_responses, $_, 1);
    }
  }
  $res->close;
  $res->continue;
}

sub handle_message {
  my ($req, $res) = @_;
  $res->streaming(0);
  $res->code(200);
  my $msg  = $req->uri->query_param('msg');
  my $chan = $req->uri->query_param('chan');
  my $session_id = $req->uri->query_param('session');
  return 200 unless $session_id;
  my $irc = $ircs{$session_id};
  return 200 unless $irc;
  if (length $msg) {
    if ($msg =~ /^\/query (\S+)/) {
      create_tab($1, $irc->session_id);
    }
    elsif ($msg =~ /^\/join (.+)/) {
      $irc->yield( join => $1);
    }
    elsif ($msg =~ /^\/part\s?(.+)?/) {
      $irc->yield( part => $1 || $chan);
    }
    elsif ($msg =~ /^\/window new/) {
      create_tab($chan, $irc->session_id);
    }
    elsif ($msg =~ /^\/n(?:ames)?/ and $chan) {
      show_nicks($chan, $irc->session_id);
    }
    elsif ($msg =~ /^\/topic\s?(.+)?/) {
      if ($1) {
        $irc->yield(topic => $chan, $1);
      }
      else {
        my $topic = $irc->channel_topic($chan, $irc->session_id);
        send_topic($topic->{SetBy}, $chan, $irc->session_id, decode_utf8($topic->{Value}));
      }
    }
    elsif ($msg =~ /^\/me (.+)/) {
      display_message($irc->nick_name, $chan, $irc->session_id, decode_utf8("• $1"));
      $irc->yield(ctcp => $chan, "ACTION $1");
    }
    else {
      log_debug("sending message to $chan");
      display_message($irc->nick_name, $chan, $irc->session_id, decode_utf8($msg)); 
      $irc->yield( privmsg => $chan => $msg);
    }
  }

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
  my $channels = [];
  for my $irc (keys %ircs) {
    for my $channel (keys %{$ircs{$irc}->channels}) {
      push @$channels, {
        name => cleanse_channel($channel),
        name_orig => $channel,
        session => $ircs{$irc}->session_id,
        topic => $ircs{$irc}->channel_topic($channel),
        server => $ircs{$irc},
      }
    }
  }
  $tt->process('index.tt', {
    channels => $channels,
  }, \$output) or die $!;
  $res->content($output);
  return 200;
}

sub handle_autocomplete {
  my ($req, $res) = @_;
  $res->code(200);
  $res->streaming(0);
  $res->content_type('text/html; charset=utf-8');
  my $query = $req->uri->query_param('msg');
  my $chan = $req->uri->query_param('chan');
  my $session_id = $req->uri->query_param('session');
  ($query) = $query =~ /((?:^\/)?[\d\w]*)$/;
  return 200 unless $query;
  log_debug("handling autocomplete for $query");
  my $irc = $ircs{$session_id};
  my @matches = grep {/^\Q$query\E/i} $irc->channel_list($chan);
  push @matches, grep {/^\Q$query\E/i} map {"/$_"} @commands;
  my $html = '';
  $tt->process('autocomplete.tt',{matches => \@matches}, \$html) or die $!;
  $res->content($html);
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
  my $irc = $_[HEAP]->{irc};
  $irc->yield( register => 'all' );
  $irc->plugin_add('Connector' => POE::Component::IRC::Plugin::Connector->new);
  $irc->yield( connect => { } );
  log_debug("connected to " . $_[HEAP]->{network});
  return;
}

sub irc_001 {
  my $irc = $_[HEAP]->{irc};
  for (@{$config->{channels}}) {
    log_debug("joining $_ on " . $irc->server_name);
    $irc->yield( join => $_ );
  }
}

sub irc_public {
  my ($who, $where, $what) = @_[ARG0 .. ARG2];
  my $irc = $_[HEAP]->{irc};
  my $nick = ( split /!/, $who )[0];
  my $channel = $where->[0];
  $what = decode("utf8", $what, Encode::FB_WARN);
  display_message($nick, $channel, $irc->session_id, $what);
}

sub irc_msg {
  my ($who, $what) = @_[ARG0, ARG2];
  my $irc = $_[HEAP]->{irc};
  my $nick = ( split /!/, $who)[0];
  $what = decode("utf8", $what, Encode::FB_WARN);
  display_message($nick, $nick, $irc->session_id, $what);
}

sub irc_ctcp_action {
  my ($who, $where, $what) = @_[ARG0 .. ARG2];
  my $irc = $_[HEAP]->{irc};
  my $nick = ( split /!/, $who )[0];
  my $channel = $where->[0];
  $what = decode("utf8", "• $what", Encode::FB_WARN);
  display_message($nick, $channel, $irc->session_id, $what);
}

sub irc_nick {
  my ($who, $new_nick) = @_[ARG0, ARG1];
  my $irc = $_[HEAP]->{irc};
  my $nick = ( split /!/, $who )[0];
  display_event($nick, $_, $irc->session_id, "nick", $new_nick)
    for $irc->nick_channels($new_nick);
}

sub irc_join {
  my ($who, $where) = @_[ARG0, ARG1];
  my $irc = $_[HEAP]->{irc};
  my $nick = ( split /!/, $who)[0];
  my $channel = $where;
  if ($nick ne $irc->nick_name) {
    display_event($nick, $channel, $irc->session_id, "joined");  
  }
  else {
    create_tab($channel, $irc->session_id);
  }
}

sub irc_chan_sync {
  my ($channel) = @_;
  my $irc = $_[HEAP]->{irc};
  create_tab($channel, $irc->session_id) if $channel ne "main";
}

sub irc_part {
  my ($who, $where, $msg) = @_[ARG0 .. ARG2];
  my $irc = $_[HEAP]->{irc};
  my $nick = ( split /!/, $who)[0];
  my $channel = $where;
  if ($nick ne $irc->nick_name) {
    display_event($nick, $channel, $irc->session_id, "left", $msg);
  }
  else {
    close_tab($channel, $irc->session_id);
  }
}

sub irc_quit {
  my ($who, $msg, $channels) = @_[ARG0 .. ARG2];
  my $irc = $_[HEAP]->{irc};
  my $nick = ( split /!/, $who)[0];
  for my $channel (@$channels) {
    display_event($nick, $channel, $irc->session_id, "left", $msg);
  }
}

sub irc_topic {
  my ($who, $channel, $topic) = @_[ARG0 .. ARG2];
  my $irc = $_[HEAP]->{irc};
  send_topic($who, $channel, $irc->session_id, $topic);
}

sub send_topic {
  my ($who, $channel, $session, $topic) = @_;
  my $nick = ( split /!/, $who)[0];
  display_event($nick, $channel, $session, "topic", $topic);
}

sub display_event {
  my ($nick, $channel, $session, $event_type, $msg) = @_;
  my $event = {
    type      => "event",
    nick      => $nick,
    chan_full => $channel,
    chan      => cleanse_channel($channel),
    session   => $session,
    event     => $event_type,
    message   => $msg,
    timestamp => make_timestamp(),
  };
  add_outgoing($event, "event");
}

sub display_message {
  my ($nick, $channel, $session, $text) = @_;
  my $html = IRC::Formatting->formatted_string_to_html($text);
  my $mynick = $ircs{$session}->nick_name;
  my $msg = {
    type      => "message",
    nick      => $nick,
    chan_full => $channel,
    chan      => cleanse_channel($channel),
    session   => $session,
    self      => $nick eq $mynick,
    html      => $html,
    highlight => $text =~ /\b$mynick\b/i || 0,
    timestamp => make_timestamp(),
  };
  add_outgoing($msg, "message");
}

sub create_tab {
  my ($name, $session) = @_;
  my $action = {
    type      => "join",
    chan_orig => $name,
    chan      => cleanse_channel($name),
    session   => $session,
    timestamp => make_timestamp(),
  };
  my $chan_html = '';
  $tt->process("channel.tt", {channel => {
    name => cleanse_channel($name), name_orig => $name, session => $session
  }}, \$chan_html);
  $action->{html}{channel} = $chan_html;
  my $tab_html = '';
  $tt->process("tab.tt", {channel => {
    name => cleanse_channel($name), name_orig => $name, session => $session
  }}, \$tab_html);
  $action->{html}{tab} = $tab_html;
  log_debug("sending a request for a new tab: $name") if @open_responses;
  push @{$_->{actions}}, $action for @open_responses;
  $_->continue for @open_responses;
}

sub close_tab {
  my ($name, $session) = @_;
  my $action = {
    type      => "part",
    chan      => cleanse_channel($name),
    session   => $session,
    timestamp => make_timestamp(),
  };
  log_debug("sending a request to close a tab: $name") if @open_responses;
  push @{$_->{actions}}, $action for @open_responses;
  $_->continue for @open_responses;
}

sub add_outgoing {
  my ($hashref, $type) = @_;
  my $html = '';
  $tt->process("$type.tt", $hashref, \$html);
  $hashref->{full_html} = $html;
  log_debug("adding $type to response queues") if @open_responses;
  push @{$_->{msgs}}, $hashref for @open_responses;
  $_->continue for @open_responses;
}

sub show_nicks {
  my ($chan, $session) = @_;
  push @{$_->{actions}}, {
    type    => "announce",
    chan    => cleanse_channel($chan),
    session => $session,
    str     => format_nick_table($ircs{$session}->channel_list($chan))
  } for @open_responses;
  $_->continue for @open_responses;
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

sub cleanse_channel {
  my $channel = shift;
  $channel =~ s/[#&]/chan_/;
  return $channel;
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
