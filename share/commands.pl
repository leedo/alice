my $SRVOPT = qr/(?:\-(\S+)\s+)?/;

my $commands = [
  {
    name => 'say',
    re => qr{^([^/].*)}s,
    code => sub {
      my ($self, $window, $msg) = @_;
      if ($window->type eq "info") {
        $self->reply($window, "You can't talk here!");
        return;
      }
      elsif (!$window->irc->is_connected) {
        $self->reply($window, "You are not connected to ".$window->irc->alias.".");
        return;
      }
      $self->app->store(nick => $window->nick, channel => $window->title, body => $msg);
      $self->show($window, $msg);
      $window->irc->send_srv(PRIVMSG => $window->title, $msg);
    },
  },
  {
    name => 'msg',
    re => qr{^/(?:msg|query)\s+$SRVOPT(\S+)(.*)},
    eg => "/MSG [-<server name>] <nick> <message>",
    desc => "Sends a message to a nick.",
    code => sub  {
      my $self = shift;
      my $window = shift;
      my ($msg, $nick, $network);
      if (@_ == 3) {
        ($msg, $nick, $network) = @_;
      }
      elsif (@_ == 2) {
        ($msg, $nick) = @_;
      }
      $msg =~ s/^\s+//;
      my $irc = $window->irc;
      if ($network and $self->app->has_irc($network)) {
        $irc = $self->app->get_irc($network);
      }
      return unless $irc;
      my $new_window = $self->app->find_or_create_window($nick, $irc);
      my @msgs = ($new_window->join_action);
      if ($msg) {
        push @msgs, $new_window->format_message($new_window->nick, $msg);
        $irc->send_srv(PRIVMSG => $nick, $msg) if $msg;
      }
      $self->broadcast(@msgs);
    },
  },
  {
    name => 'nick',
    re => qr{^/nick\s+$SRVOPT(\S+)},
    eg => "/NICK [-<server name>] <new nick>",
    desc => "Changes your nick.",
    code => sub {
      my ($self, $window, $nick, $network) = @_;
      my $irc;
      if ($network and $self->app->has_irc($network)) {
        $irc = $self->app->get_irc($network);
      } else {
        $irc = $window->irc;
      }
      $irc->log(info => "now known as $nick");
      $irc->send_srv(NICK => $nick);
    },
  },
  {
    name => 'names',
    re => qr{^/n(?:ames)?(?:\s(-a(?:vatars)?))?},
    in_channel => 1,
    eg => "/NAMES [-avatars]",
    desc => "Lists nicks in current channel. Pass the -avatars option to display avatars with the nicks.",
    code => sub  {
      my ($self, $window, $avatars) = @_;
      $self->reply($window, $window->nick_table($avatars));
    },
  },
  {
    name => 'join',
    re => qr{^/j(?:oin)?\s+$SRVOPT(.+)},
    eg => "/JOIN [-<server name>] <channel> [<password>]",
    desc => "Joins the specified channel.",
    code => sub  {
      my ($self, $window, $channel, $network) = @_;
      my $irc;
      if ($network and $self->app->has_irc($network)) {
        $irc = $self->app->get_irc($network);
      } else {
        $irc = $window->irc;
      }
      my @params = split /\s+/, $channel;
      if ($irc and $irc->cl->is_channel_name($params[0])) {
        $irc->log(info => "joining $params[0]");
        $irc->send_srv(JOIN => @params);
      }
    },
  },
  {
    name => 'create',
    re => qr{^/create\s+(\S+)},
    code => sub  {
      my ($self, $window, $name) = @_;
      my $new_window = $self->app->find_or_create_window($name, $window->irc);
      $self->broadcast($new_window->join_action);
    },
  },
  {
    name => 'part',
    re => qr{^/(?:close|wc|part)},
    eg => "/PART",
    desc => "Leaves and closes the focused window.",
    code => sub  {
      my ($self, $window) = @_;
      $window->is_channel ? $window->irc->send_srv(PART => $window->title)
      : $self->app->close_window($window);
    },
  },
  {
    name => 'clear',
    re => qr{^/clear},
    eg => "/CLEAR",
    desc => "Clears lines from current window.",
    code => sub {
      my ($self, $window) = @_;
      $window->buffer->clear;
      $self->broadcast($window->clear_action);
    },
  },
  {
    name => 'topic',
    re => qr{^/t(?:opic)?(?:\s+(.+))?},
    in_channel => 1,
    eg => "/TOPIC [<topic>]",
    desc => "Shows and/or changes the topic of the current channel.",
    code => sub  {
      my ($self, $window, $new_topic) = @_;
      if ($new_topic) {
        $window->topic({string => $new_topic, nick => $window->nick, time => time});
        $window->irc->send_srv(TOPIC => $window->title, $new_topic);
      }
      else {
        my $topic = $window->topic;
        $self->broadcast($window->format_event("topic", $topic->{author}, $topic->{string}));
      }
    },
  },
  {
    name => 'whois',
    re => qr{^/whois(?:\s+(-f(?:orce)?))?\s+(\S+)},
    eg => "/WHOIS [-force] <nick>",
    desc => "Shows info about the specified nick. Use -force option to refresh",
    code => sub  {
      my ($self, $window, $nick, $force) = @_;
      if (!$force and $window->irc->includes_nick($nick)) {
        $self->reply($window, $window->irc->whois_table($nick));
      }
      else {
        $window->irc->add_whois_cb($nick => sub {
            $self->reply($window, $window->irc->whois_table($nick));
          });
      }
    },
  },
  {
    name => 'me',
    re => qr{^/me\s+(.+)},
    eg => "/ME <message>",
    desc => "Sends a CTCP ACTION to the current window.",
    code => sub {
      my ($self, $window, $action) = @_;
      $self->show($window, "• $action");
      $window->irc->send_srv(PRIVMSG => $window->title, chr(01) . "ACTION $action" . chr(01));
    },
  },
  {
    name => 'quote',
    re => qr{^/(?:quote|raw)\s+(.+)},
    eg => "/QUOTE <data>",
    desc => "Sends the server raw data without parsing.",
    code => sub  {
      my ($self, $window, $command) = @_;
      $window->irc->send_raw($command);
    },
  },
  {
    name => 'disconnect',
    re => qr{^/disconnect\s+(\S+)},
    eg => "/DISCONNECT <server name>",
    desc => "Disconnects from the specified server.",
    code => sub  {
      my ($self, $window, $network) = @_;
      my $irc = $self->app->get_irc($network);
      if ($irc and $irc->is_connected) {
        $irc->disconnect;
      }
      elsif ($irc->reconnect_timer) {
        $irc->cancel_reconnect;
        $irc->log(info => "canceled reconnect");
      }
      else {
        $self->reply($window, "already disconnected");
      }
    },
  },
  {
    name => 'connect',
    re => qr{^/connect\s+(\S+)},
    eg => "/CONNECT <server name>",
    desc => "Connects to the specified server.",
    code => sub {
      my ($self, $window, $network) = @_;
      my $irc  = $self->app->get_irc($network);
      if ($irc and !$irc->is_connected) {
        $irc->connect;
      }
    },
  },
  {
    name => 'ignore',
    re => qr{^/ignore\s+(\S+)},
    eg => "/IGNORE <nick>",
    desc => "Adds nick to ignore list.",
    code => sub  {
      my ($self, $window, $nick) = @_;
      $self->app->add_ignore($nick);
      $self->reply($window, "Ignoring $nick");
    },
  },
  {
    name => 'unignore',
    re => qr{^/unignore\s+(\S+)},
    eg => "/UNIGNORE <nick>",
    desc => "Removes nick from ignore list.",
    code => sub {
      my ($self, $window, $nick) = @_;
      $self->app->remove_ignore($nick);
      $self->reply($window, "No longer ignoring $nick");
    },
  },
  {
    name => 'ignores',
    re => qr{^/ignores?},
    eg => "/IGNORES",
    desc => "Lists ignored nicks.",
    code => sub {
      my ($self, $window) = @_;
      my $msg = join ", ", $self->app->ignores;
      $msg = "none" unless $msg;
      $self->reply($window, "Ignoring:\n$msg");
    },

  },
  {
    name => 'window',
    re => qr{^/w(?:indow)?\s+(\d+|next|prev(?:ious)?)},
    eg => "/WINDOW <window number>",
    desc => "Focuses the provided window number",
    code => sub  {
      my ($self, $window, $window_number) = @_;
      $self->broadcast({
        type => "action",
        event => "focus",
        window_number => $window_number,
      });
    },
  },
  {
    name => 'help',
    re => qr{^/help(?:\s+(\S+))?},
    code => sub {
      my ($self, $window, $command) = @_;
      if (!$command) {
        $self->reply($window, '/HELP <command> for help with a specific command');
        $self->reply($window, "Available commands: " . join " ", map {
          uc $_->{name};
        } grep {$_->{eg}} @{$self->handlers});
        return;
      }
      for (@{$self->handlers}) {
        if ($_->{name} eq lc $command) {
          $self->reply($window, "$_->{eg}\n$_->{desc}");
          return;
        }
      }
      $self->reply($window, "No help for ".uc $command);
    },
  },
  {
    name => 'notfound',
    re => qr{^/(.+)(?:\s.*)?},
    code => sub {
      my ($self, $window, $command) = @_;
      $self->reply($window, "Invalid command $command");
    },
  },
];

$commands;
