my $SRVOPT = qr/(?:\-(\S+)\s+)?/;

[
  {
    sub => '_say',
    re => qr{^([^/].*)}s,
  },
  {
    sub => 'msg',
    re => qr{^/(?:msg|query)\s+$SRVOPT(\S+)(.*)},
    eg => "/MSG [-<server name>] <nick> <message>",
    desc => "Sends a message to a nick."
  },
  {
    sub => 'nick',
    re => qr{^/nick\s+$SRVOPT(\S+)},
    eg => "/NICK [-<server name>] <new nick>",
    desc => "Changes your nick.",
  },
  {
    sub => 'names',
    re => qr{^/n(?:ames)?(?:\s(-a(?:vatars)?))?},
    in_channel => 1,
    eg => "/NAMES [-avatars]",
    desc => "Lists nicks in current channel. Pass the -avatars option to display avatars with the nicks.",

  },
  {
    sub => '_join',
    re => qr{^/j(?:oin)?\s+$SRVOPT(.+)},
    eg => "/JOIN [-<server name>] <channel> [<password>]",
    desc => "Joins the specified channel.",
  },
  {
    sub => 'create',
    re => qr{^/create\s+(\S+)},
  },
  {
    sub => 'part',
    re => qr{^/(?:close|wc|part)},
    eg => "/PART",
    desc => "Leaves and closes the focused window.",
  },
  {
    sub => 'clear',
    re => qr{^/clear},
    eg => "/CLEAR",
    desc => "Clears lines from current window.",
  },
  {
    sub => 'topic',
    re => qr{^/t(?:opic)?(?:\s+(.+))?},
    in_channel => 1,
    eg => "/TOPIC [<topic>]",
    desc => "Shows and/or changes the topic of the current channel.",
  },
  {
    sub => 'whois',
    re => qr{^/whois(?:\s+(-f(?:orce)?))?\s+(\S+)},
    eg => "/WHOIS [-force] <nick>",
    desc => "Shows info about the specified nick. Use -force option to refresh",
  },
  {
    sub => 'me',
    re => qr{^/me\s+(.+)},
    eg => "/ME <message>",
    desc => "Sends a CTCP ACTION to the current window.",
  },
  {
    sub => 'quote',
    re => qr{^/(?:quote|raw)\s+(.+)},
    eg => "/QUOTE <data>",
    desc => "Sends the server raw data without parsing.",
  },
  {
    sub => 'disconnect',
    re => qr{^/disconnect\s+(\S+)},
    eg => "/DISCONNECT <server name>",
    desc => "Disconnects from the specified server.",
  },
  {
    sub => 'connect',
    re => qr{^/connect\s+(\S+)},
    eg => "/CONNECT <server name>",
    desc => "Connects to the specified server.",
  },
  {
    sub => 'ignore',
    re => qr{^/ignore\s+(\S+)},
    eg => "/IGNORE <nick>",
    desc => "Adds nick to ignore list.",
  },
  {
    sub => 'unignore',
    re => qr{^/unignore\s+(\S+)},
    eg => "/UNIGNORE <nick>",
    desc => "Removes nick from ignore list.",
  },
  {
    sub => 'ignores',
    re => qr{^/ignores?},
    eg => "/IGNORES",
    desc => "Lists ignored nicks.",
  },
  {
    sub => 'window',
    re => qr{^/w(?:indow)?\s+(\d+|next|prev(?:ious)?)},
    eg => "/WINDOW <window number>",
    desc => "Focuses the provided window number",
  },
  {
    sub => 'help',
    re => qr{^/help(?:\s+(\S+))?},
  },
  {
    sub => 'notfound',
    re => qr{^/(.+)(?:\s.*)?},
  },
]
