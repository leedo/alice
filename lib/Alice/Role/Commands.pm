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
  my ($self, $stream, $window, $line) = @_;

  try {
    my ($command, $arg) = $self->match_irc_command($line);
    if ($command) {
      $self->run_irc_command($command, $arg, {
        stream => $stream,
        window => $window,
      });
    }
    else {
      throw UnknownCommand $line ." does not match any known commands. Try /help";
    }
  }
  catch {
    $stream->reply("$_");
  }
}

sub match_irc_command {
  my ($self, $line) = @_;

  $line = "/say $line" unless substr($line, 0, 1) eq "/";

  for my $name (keys %COMMANDS) {

    if ($line =~ m{^/$name\b\s?(.*)}) {
      my $arg = $1;
      return ($name, $arg);
    }
  }
}

sub run_irc_command {
  my ($self, $name, $arg, $req) = @_;
  my $command = $COMMANDS{$name};
  my @args;

  # must be in a channel
  my $type = $req->{window}->type;
  if ($command->{window_type} and none {$_ eq $type} @{$command->{window_type}}) {
    my $types = join " or ", @{$command->{window_type}};
    throw ChannelRequired "Must be in a $types for /$command->{name}.";
  }

  my $network = $req->{window}->network;

  # determine the network can be overridden
  if ($command->{network} and $arg =~ s/^\s*$SRVOPT//) {
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

    $req->{irc} = $irc;
  }

  # gather any options
  if (my $opt_re = $command->{args}) {
    unless (@args = ($arg =~ /$opt_re/)) {
      throw InvalidArguments $command->{eg};
    }
  }

  $command->{cb}->($self, $req, @args);
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
  args => qr{(.+)},
  cb => sub {
    my ($self, $req, $msg) = @_;

    $self->send_message($req->{window}, $req->{irc}->nick, $msg);
    $req->{irc}->send_long_line(PRIVMSG => $req->{window}->title, $msg);
  },
};

command qr{msg|query|q} => {
  name => "msg",
  args => qr{(\S+)\s*(.*)},
  eg => "/MSG [-<network>] <nick> [<msg>]",
  desc => "Sends a message to a nick.",
  connection => 1,
  network => 1,
  cb => sub  {
    my ($self, $req, $nick, $msg) = @_;

    my $new_window = $self->find_or_create_window($nick, $req->{irc});
    $self->broadcast($new_window->join_action);

    if ($msg) {
      $self->send_message($new_window, $req->{irc}->nick, $msg);
      $req->{irc}->send_srv(PRIVMSG => $nick, $msg);
    }
  }
};

command nick => {
  name => "nick",
  args => qr{(\S+)},
  connection => 1,
  network => 1,
  eg => "/NICK [-<network>] <new nick>",
  desc => "Changes your nick.",
  cb => sub {
    my ($self, $req, $nick) = @_;

    $req->{stream}->reply("changing nick to $nick on " . $req->{irc}->name);
    $self->config->servers->{$req->{irc}->name}{nick} = $nick;
    $req->{irc}->send_srv(NICK => $nick);
  }
};

command qr{names|n} => {
  name => "names",
  window_type => [qw/channel/],
  connection => 1,
  eg => "/NAMES",
  desc => "Lists nicks in current channel.",
  cb => sub  {
    my ($self, $req) = @_;
    my @nicks = $req->{irc}->channel_nicks($req->{window}->title, 1);
    $req->{stream}->reply(nick_table(@nicks));
  },
};

command qr{join|j} => {
  name => "join",
  args => qr{(\S+)\s*(\S+)?},
  connection => 1,
  network => 1,
  eg => "/JOIN [-<network>] <channel> [<password>]",
  desc => "Joins the specified channel.",
  cb => sub  {
    my ($self, $req, $channel, $password) = @_;

    $req->{stream}->reply("joining $channel on ". $req->{irc}->name);
    $channel .= " $password" if $password;
    $req->{irc}->send_srv(JOIN => $channel);
  },
};

command create => {
  name => "create",
  args => qr{(\S+)},
  connection => 1,
  network => 1,
  cb => sub  {
    my ($self, $req, $name) = @_;

    my $new_window = $self->find_or_create_window($name, $req->{irc});
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
    my $window = $req->{window};

    $self->close_window($window);
    my $irc = $self->get_irc($window->network);

    if ($irc and $window->is_channel and $irc->is_connected) {
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
    $self->broadcast($req->{window}->clear_action);
  },
};

command qr{topic|t} => {
  name => 'topic',
  args => qr{(.+)?},
  window_type => ['channel'],
  connection => 1,
  network => 1,
  eg => "/TOPIC [<topic>]",
  desc => "Shows and/or changes the topic of the current channel.",
  cb => sub  {
    my ($self, $req, $new_topic) = @_;

    my $window = $req->{window};

    if ($new_topic) {
      $window->topic({string => $new_topic, nick => $req->{irc}->nick, time => time});
      $req->{irc}->send_srv(TOPIC => $window->title, $new_topic);
    }
    else {
      $self->send_event($window, topic => $window->topic->{nick}, $window->topic_string);
    }
  }
};

command whois =>  {
  name => 'whois',
  connection => 1,
  network => 1,
  args => qr{(\S+)},
  eg => "/WHOIS [-<network>] <nick>",
  desc => "Shows info about the specified nick",
  cb => sub  {
    my ($self, $req, $nick) = @_;

    my $irc = $req->{irc};

    $irc->add_whois($nick,sub {
      $req->{stream}->reply($_[0] ? $_[0] : "No such nick: $nick on " . $irc->name);
    });
  }
};

command me =>  {
  name => 'me',
  args => qr{(.+)},
  eg => "/ME <message>",
  window_type => [qw/channel privmsg/],
  connection => 1,
  desc => "Sends a CTCP ACTION to the current window.",
  cb => sub {
    my ($self, $req, $action) = @_;

    $self->send_message($req->{window}, $req->{irc}->nick, "\x{2022} $action");
    $action = AnyEvent::IRC::Util::encode_ctcp(["ACTION", $action]);
    $req->{irc}->send_srv(PRIVMSG => $req->{window}->title, $action);
  },
};

command quote => {
  name => 'quote',
  args => qr{(.+)},
  connection => 1,
  network => 1,
  eg => "/QUOTE [-<network>] <data>",
  desc => "Sends the server raw data without parsing.",
  cb => sub  {
    my ($self, $req, $msg) = @_;
    $req->{irc}->send_raw($msg);
  },
};

command disconnect => {
  name => 'disconnect',
  args => qr{(\S+)},
  eg => "/DISCONNECT <network>",
  desc => "Disconnects from the specified server.",
  cb => sub  {
    my ($self, $req, $network) = @_;
    $req->{stream}->reply("attempting to disconnect from $network");
    $self->disconnect_irc($network);
  },
};

command 'connect' => {
  name => 'connect',
  args => qr{(\S+)},
  eg => "/CONNECT <network>",
  desc => "Connects to the specified server.",
  cb => sub {
    my ($self, $req, $network) = @_;
    $req->{stream}->reply("attempting to connect to $network");
    $self->connect_irc($network);
  }
};

command ignore =>  {
  name => 'ignore',
  args => qr{(\S+)?\s*(\S+)?},
  eg => "/IGNORE [<type>] <target>",
  desc => "Adds a nick or channel to ignore list. Types include 'msg', 'part', 'join'. Defaults to 'msg'.",
  cb => sub  {
    my ($self, $req, @opts) = @_;
    
    if (!$opts[0]) {
      return $COMMANDS{ignores}->{cb}->($self, $req);
    }

    unshift @opts, "msg" unless $opts[1];
    my ($type, $nick) = @opts;

    $self->add_ignore($type, $nick);
    $req->{stream}->reply("Ignoring $type from $nick");
  },
};

command unignore =>  {
  name => 'unignore',
  args => qr{(\S+)\s*(\S+)?},
  eg => "/UNIGNORE [<type>] <nick>",
  desc => "Removes nick from ignore list. Types include 'msg', 'part', 'join'. Defaults to 'msg'.",
  cb => sub {
    my ($self, $req, @opts) = @_;
    
    unshift @opts, "msg" unless $opts[1];
    my ($type, $nick) = @opts;

    $self->remove_ignore($type, $nick);
    $req->{stream}->reply("No longer ignoring $nick");
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

    $req->{stream}->reply("Ignoring\n$msg");
  },
};

command qr{window|w} =>  {
  name => 'window',
  args => qr{(\d+|next|prev(?:ious)?)},
  eg => "/WINDOW <window number>",
  desc => "Focuses the provided window number",
  cb => sub  {
    my ($self, $req, $num) = @_;
    
    $req->{stream}->send({
      type => "action",
      event => "focus",
      window_number => $num,
    });
  }
};

command away =>  {
  name => 'away',
  args => qr{(.+)?},
  eg => "/AWAY [<message>]",
  desc => "Set or remove an away message",
  cb => sub {
    my ($self, $req, $message) = @_;

    if ($message) {
      $req->{stream}->reply("Setting away status: $message");
      $self->set_away($message);
    }
    else {
      $req->{stream}->reply("Removing away status.");
      $self->set_away;
    }
  }
};

command invite =>  {
  name => 'invite',
  connection => 1,
  args => qr{(\S+)\s+(\S+)},
  eg => "/INVITE <nickname> <channel>",
  desc => "Invite a user to a channel you're in",
  cb => sub {
    my ($self, $req, $nick, $channel) = @_;

    $req->{stream}->reply("Inviting $nick to $channel");
    $req->{irc}->send_srv(INVITE => $nick, $channel);   
  },
};

command mode => {
  name => 'mode',
  args => qr{(\S+)\s+([+-]\S+)},
  eg => '/MODE <target> <+/-><mode>',
  connection => 1,
  window_type => ['channel'],
  desc => "Sets a mode",
  cb => sub {
    my ($self, $req, $target, $mode) = @_;
    my $channel = $req->{window}->title;
    $req->{irc}->send_srv(MODE => $channel, $mode, $target);
  },
};

command kick => {
  name => 'kick',
  args => qr{(\S+)},
  eg => '/KICK <nick> [message]',
  connection => 1,
  window_type => ['channel'],
  desc => "Kicks a user with an optional message",
  cb => sub {
    my ($self, $req, $nick, $message) = @_;
    $message = "" unless defined $message;
    my $channel = $req->{window}->title;
    $req->{irc}->send_srv(KICK => $channel, $nick, $message);
  }
};

command help => {
  name => 'help',
  eg => "/HELP [<command>]",
  desc => "Shows list of commands or overview of a specific command.",
  args => qr{(\S+)?},
  cb => sub {
    my ($self, $req, $command) = @_;

    if (!$command) {
      my $commands = join " ", map {uc $_->{name}} grep {$_->{eg}} values %COMMANDS;
      $req->{stream}->reply('/HELP <command> for help with a specific command');
      $req->{stream}->reply("Available commands: $commands");
      return;
    }

    for (values %COMMANDS) {
      if ($_->{name} eq lc $command) {
        $req->{stream}->reply("$_->{eg}\n$_->{desc}");
        return;
      }
    }

    $req->{stream}->reply("No help for ".uc $command);
  }
};

command chunk => {
  name => 'chunk',
  args => qr{(-?\d+) (\d+)},
  cb => sub {
    my ($self, $req, $max, $limit) = @_;
    $self->update_window($req->{stream}, $req->{window}->id, $max, $limit);
  }
};

command trim => {
  name => 'trim',
  eg => "/TRIM [<number>]",
  desc => "Trims the current tab to <number> of lines. Defaults to 50.",
  window => 1,
  args => qr{(\d+)?},
  cb => sub {
    my ($self, $req, $lines) = @_;
    $lines ||= 50;
    $req->{stream}->send($req->{window}->trim_action($lines));
  }
};

sub nick_table {
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

1;
