package Alice::Role::Commands;

use Any::Moose 'Role';

use List::MoreUtils qw/none/;
use Try::Tiny;
use Class::Throwable qw/NetworkRequired InvalidNetwork ChannelRequired
                        InvalidArguments UnknownCommand/;

our %COMMANDS;
my $SRVOPT = qr/\-(\S+)\s*/;

sub commands {
  return grep {$_->{eg}} values %COMMANDS;
}

sub irc_command {
  my ($self, $req) = @_;

  try {
    my ($command, $args) = $self->match_irc_command($req->line);
    if ($command) {
      $self->run_irc_command($command, $req, $args);
    }
    else {
      throw UnknownCommand $req->line ." does not match any known commands. Try /help";
    }
  }
  catch {
    $req->reply("$_");
  }
}

sub match_irc_command {
  my ($self, $line) = @_;

  $line = "/say $line" unless substr($line, 0, 1) eq "/";

  for my $name (keys %COMMANDS) {

    if ($line =~ m{^/$name\b\s*(.*)}) {
      my $args = $1;
      return ($name, $args);
    }
  }
}

sub run_irc_command {
  my ($self, $name, $req, $args) = @_;
  my $command = $COMMANDS{$name};
  my $opts = [];

  # must be in a channel
  my $type = $req->window->type;
  if ($command->{window_type} and none {$_ eq $type} @{$command->{window_type}}) {
    my $types = join " or ", @{$command->{window_type}};
    throw ChannelRequired "Must be in a $types for /$command->{name}.";
  }

  my $network = $req->window->network;

  # determine the network can be overridden
  if ($command->{network} and $args =~ s/^$SRVOPT//) {
    $network = $1;
  }

  # command requires a connected network
  if ($command->{connection}) {
    throw NetworkRequired $command->{eg} unless $network; 

    my $irc = $self->get_irc($network);

    throw InvalidNetwork "The $network network does not exist."
      unless $irc;

    throw InvalidNetwork "The $network network is not connected"
      unless $irc->is_connected;

    $req->irc($irc);
  }

  # gather any options
  if (my $opt_re = $command->{opts}) {
    if (my (@opts) = ($args =~ /$opt_re/)) {
      $opts = \@opts;
    }
    else {
      throw InvalidArguments $command->{eg};
    }
  }

  $command->{cb}->($self, $req, $opts);
}

sub command {
  my ($name, $opts) = @_;

  if ($opts) {
    $COMMANDS{$name} = $opts;
  }

  return $COMMANDS{$name};
}

command say => {
  name => "say",
  window_type => [qw/channel privmsg/],
  connection => 1,
  eg => "/SAY <msg>",
  opts => qr{(.+)},
  cb => sub {
    my ($self, $req, $opts) = @_;

    my $msg = $opts->[0];
    $self->send_message($req->window, $req->irc->nick, $msg);
    $req->irc->send_long_line(PRIVMSG => $req->window->title, $msg);
  },
};

command msg => {
  name => "msg",
  opts => qr{(\S+)\s*(.*)},
  eg => "/MSG [-<network>] <nick> [<msg>]",
  desc => "Sends a message to a nick.",
  connection => 1,
  network => 1,
  cb => sub  {
    my ($self, $req, $opts) = @_;

    my ($nick, $msg) = @$opts;

    my $new_window = $self->find_or_create_window($nick, $req->irc);
    $self->broadcast($new_window->join_action);

    if ($msg) {
      $self->send_message($new_window, $req->nick, $msg);
      $req->send_srv(PRIVMSG => $nick, $msg);
    }
  }
};

command nick => {
  name => "nick",
  opts => qr{(\S+)},
  connection => 1,
  network => 1,
  eg => "/NICK [-<network>] <new nick>",
  desc => "Changes your nick.",
  cb => sub {
    my ($self, $req, $opts) = @_;

    my $nick = $opts->[0];

    $req->reply("changing nick to $nick on " . $req->irc->name);
    $req->irc->send_srv(NICK => $nick);
  }
};

command qr{names|n} => {
  name => "names",
  window_type => [qw/channel/],
  connection => 1,
  eg => "/NAMES [-avatars]",
  desc => "Lists nicks in current channel.",
  cb => sub  {
    my ($self, $req) = @_;
    my @nicks = $req->irc->channel_nicks($req->window->title);
    $req->reply($req->window->nick_table(@nicks));
  },
};

command qr{join|j} => {
  name => "join",
  opts => qr{(\S+)\s*(\S+)?},
  connection => 1,
  network => 1,
  eg => "/JOIN [-<network>] <channel> [<password>]",
  desc => "Joins the specified channel.",
  cb => sub  {
    my ($self, $req, $opts) = @_;

    my $channel = $opts->[0];
    $req->reply("joining $channel on ". $req->irc->name);
    $req->send_srv(JOIN => @$opts);
  },
};

command create => {
  name => "create",
  opts => qr{(\S+)},
  connection => 1,
  network => 1,
  cb => sub  {
    my ($self, $req, $opts) = @_;

    my $name = $opts->[0];

    my $new_window = $self->find_or_create_window($name, $req->irc);
    $self->broadcast($new_window->join_action);
  }
};

command qr{close|wc|part} => {
  name => 'part',
  window_type => [qw/channel privmsg/],
  eg => "/PART",
  network => 1,
  desc => "Leaves and closes the focused window.",
  cb => sub  {
    my ($self, $req) = @_;
    my $window = $req->window;

    $self->close_window($window);
    my $irc = $self->get_irc($window->network);

    if ($window->is_channel and $irc->is_connected) {
      $irc->send_srv(PART => $window->title);
    }
  },
};

command clear =>  {
  name => 'clear',
  eg => "/CLEAR",
  desc => "Clears lines from current window.",
  cb => sub {
    my ($self, $req) = @_;
    $req->window->buffer->clear;
    $self->broadcast($req->window->clear_action);
  },
};

command qr{topic|t} => {
  name => 'topic',
  opts => qr{(.+)?},
  window_type => ['channel'],
  connection => 1,
  network => 1,
  eg => "/TOPIC [<topic>]",
  desc => "Shows and/or changes the topic of the current channel.",
  cb => sub  {
    my ($self, $req, $opts) = @_;

    my $new_topic = $opts->[0];

    if ($new_topic) {
      $req->window->topic({string => $new_topic, nick => $req->nick, time => time});
      $req->send_srv(TOPIC => $req->window->title, $new_topic);
    }
    else {
      $req->stream->send($req->window->format_topic);
    }
  }
};

command whois =>  {
  name => 'whois',
  connection => 1,
  network => 1,
  opts => qr{(\S+)},
  eg => "/WHOIS [-<network>] <nick>",
  desc => "Shows info about the specified nick",
  cb => sub  {
    my ($self, $req, $opts) = @_;

    my $nick = $opts->[0];
    my $irc = $req->irc;

    $irc->add_whois($nick,sub {
      $req->reply($_[0] ? $_[0] : "No such nick: $nick on " . $irc->name);
    });
  }
};

command me =>  {
  name => 'me',
  opts => qr{(.+)},
  eg => "/ME <message>",
  window_type => [qw/channel privmsg/],
  connection => 1,
  desc => "Sends a CTCP ACTION to the current window.",
  cb => sub {
    my ($self, $req, $opts) = @_;
    my $action = $opts->[0];

    $self->send_message($req->window, $req->nick, "\x{2022} $action");
    $action = AnyEvent::IRC::Util::encode_ctcp(["ACTION", $action]);
    $req->send_srv(PRIVMSG => $req->window->title, $action);
  },
};

command quote => {
  name => 'quote',
  opts => qr{(.+)},
  connection => 1,
  network => 1,
  eg => "/QUOTE [-<network>] <data>",
  desc => "Sends the server raw data without parsing.",
  cb => sub  {
    my ($self, $req, $opts) = @_;
    $req->irc->send_raw($opts->[0]);
  },
};

command disconnect => {
  name => 'disconnect',
  opts => qr{(\S+)},
  eg => "/DISCONNECT <network>",
  desc => "Disconnects from the specified server.",
  cb => sub  {
    my ($self, $req, $opts) = @_;
    my $network = $opts->[0];
    $self->disconnect_irc($network);
  },
};

command 'connect' => {
  name => 'connect',
  opts => qr{(\S+)},
  eg => "/CONNECT <network>",
  desc => "Connects to the specified server.",
  cb => sub {
    my ($self, $req, $opts) = @_;
    my $network = $opts->[0];
    $self->connect_irc($network);
  }
};

command ignore =>  {
  name => 'ignore',
  opts => qr{(\S+)\s*(\S+)?},
  eg => "/IGNORE [<type>] <target>",
  desc => "Adds a nick or channel to ignore list. Types include 'msg', 'part', 'join'. Defaults to 'msg'.",
  cb => sub  {
    my ($self, $req, $opts) = @_;
    
    if (!$opts->[1]) {
      unshift @$opts, "msg";
    }

    my ($type, $nick) = @$opts;

    $self->add_ignore($type, $nick);
    $req->reply("Ignoring $type from $nick");
  },
};

command unignore =>  {
  name => 'unignore',
  opts => qr{(\S+)\s*(\S+)?},
  eg => "/UNIGNORE [<type>] <nick>",
  desc => "Removes nick from ignore list. Types include 'msg', 'part', 'join'. Defaults to 'msg'.",
  cb => sub {
    my ($self, $req, $opts) = @_;
    
    if (!$opts->[1]) {
      unshift @$opts, "msg";
    }

    my ($type, $nick) = @$opts;

    $self->remove_ignore($type, $nick);
    $req->reply("No longer ignoring $nick");
  },
};

command ignores => {
  name => 'ignores',
  eg => "/IGNORES",
  desc => "Lists ignored nicks.",
  cb => sub {
    my ($self, $req) = @_;

    my $msg;

    for my $type(qw/msg part join/) {
      $msg .= "$type: ";
      $msg .= (join ", ", $self->ignores($type)) || "none";
      $msg .= "\n";
    }

    $req->reply("Ignoring\n$msg");
  },
};

command qr{window|w} =>  {
  name => 'window',
  opts => qr{(\d+|next|prev(?:ious)?)},
  eg => "/WINDOW <window number>",
  desc => "Focuses the provided window number",
  cb => sub  {
    my ($self, $req, $opts) = @_;
    
    $req->stream->send({
      type => "action",
      event => "focus",
      window_number => $opts->[0],
    });
  }
};

command away =>  {
  name => 'away',
  opts => qr{(.+)?},
  eg => "/AWAY [<message>]",
  desc => "Set or remove an away message",
  cb => sub {
    my ($self, $req, $opts) = @_;

    if (my $message = $opts->[0]) {
      $req->reply("Setting away status: $message");
      $self->set_away($message);
    }
    else {
      $req->reply("Removing away status.");
      $self->set_away;
    }
  }
};

command invite =>  {
  name => 'invite',
  connection => 1,
  opts => qr{(\S+)\s+(\S+)},
  eg => "/INVITE <nickname> <channel>",
  desc => "Invite a user to a channel you're in",
  cb => sub {
    my ($self, $req, $opts) = @_;

    my ($nick, $channel) = @$opts;

    $req->reply("Inviting $nick to $channel");
    $req->send_srv(INVITE => $nick, $channel);   
  },
};

command help => {
  name => 'help',
  eg => "/HELP [<command>]",
  desc => "Shows list of commands or overview of a specific command.",
  opts => qr{(\S+)?},
  cb => sub {
    my ($self, $req, $opts) = @_;

    my $command = $opts->[0];

    if (!$command) {
      my $commands = join " ", map {uc $_->{name}} grep {$_->{eg}} values %COMMANDS;
      $req->reply('/HELP <command> for help with a specific command');
      $req->reply("Available commands: $commands");
      return;
    }

    for (values %COMMANDS) {
      if ($_->{name} eq lc $command) {
        $req->reply("$_->{eg}\n$_->{desc}");
        return;
      }
    }

    $req->reply("No help for ".uc $command);
  }
};

command chunk => {
  name => 'chunk',
  opts => qr{(\d+) (\d+)},
  cb => sub {
    my ($self, $req, $opts) = @_;
    my $window = $req->window;

    $self->update_window($req->stream, $window, $opts->[1], 0, $opts->[0], 0);
  }
};

command trim => {
  name => 'trim',
  eg => "/TRIM [<number>]",
  desc => "Trims the current tab to <number> of lines. Defaults to 50.",
  window => 1,
  opts => qr{(\d+)?},
  cb => sub {
    my ($self, $req, $opts) = @_;
    my $lines = $opts->[0] || 50;
    $req->stream->send($req->window->trim_action($lines));
  }
};

1;
