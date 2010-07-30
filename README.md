# NAME

App::Alice - an Altogether Lovely Internet Chatting Experience

# SYNPOSIS

    arthur:~ leedo$ alice
    Location: http://localhost:8080/

![Screenshot](http://static.usealice.org/whatisalice.png)

# DESCRIPTION

Alice is an IRC client that is viewed in the web browser. Alice
runs in the background maintaining connections and collecting
messages. When a browser connects, it will display the 100 most
recent messages for each channel, and update with any new messages
as they arrive.

Alice also logs messages to an SQLite database. These logs are
searchable through the web interface.

# USAGE

Installation will add a new `alice` command to start the alice
server.  When the command is run it will start the daemon and print
the URL to load in your browser.

## COMMANDLINE OPTIONS

- -d --debug

Print out additional debug information. Useful for development or
finding out if something is wrong.

- -p --port

This will change the port that the HTTP server listens on. The
default port is 8080.

- -a --address

This will change the IP address that the HTTP server listens on.
The default address is 127.0.0.1. That means alice only accepts
local connections by default. If you want to connect to alice
remotely you should change it to the IP you want to listen on, or
0.0.0.0 to listen on all addresses.

# CONFIGURATION

Most of alice can be configured through the web interface. There
are two windows that can be used to alter the configuration,
Connections and Preferences. To bring up either of these windows
click the gear icon in the bottom right hand corner of the page.

This __should__ bring up the new window. Some browsers (specifically
Chrome) will block this popup by default. If it doesn't appear make
sure that you allow popups!

## CONNECTION WINDOW

The connection window is used to add or remove servers. It should be
familiar if you have ever used an IRC client (and I assume you have.)

The only difference of note is the "Avatar" field. In reality, this field
just sets the __realname__. Alice abuses this field to get avatars for users.
If a user has an image URL or an email address as their realname, alice
will display the image next too their messages. This feature can be disabled
in the Preferences window.

## PREFERENCES WINDOW

The Preferences window can be used to set configuration options that
are not connection specific. You can toggle the use of avatars, timestamps,
and notifications. You can also edit a list of highlightable terms.

## HTTP AUTHENTICATION

Some configuration options do not have a UI yet. The most notable
of these options is HTTP authentication. If you would like to use
HTTP authentication, you will have to edit your configuration file
by hand. You can find this file at ~/.alice/config.

The config is simply a perl hash. So, if you are familiar with perl it
should not be too intimidating. If you do not know perl, sorry! :)

You will need to add "user" and "pass" values to the "auth" hash.
The resulting section of configuration might look like this:

    'auth' => {
      'user' => 'lee',
      'pass' => 'mypassword',
    },

# COMMANDS

- /j[oin] [-network] $channel

Takes a channel name as an argument, and an optional network flag.
If no network flag is provided, it will use the network of the
current tab.

- /close

Closes the current tab. If used in a channel it will also part the
channel.

__/wc__ and __/part__ are aliases for /close

- /clear

This will clear the current tab's messages from your browser. It
will also clear the tab's message buffer so when you refresh your
browser the messages won't re-appear.

- /msg [-network] $nick [$msg]

Takes a nick as an argument and an optional network flag. If no
network flag is provided, it will use the network of the current
tab. A third argument may be used for the message text. If no message
text is provided, a blank tab will be opened.

__/query__ is an alias for /msg

- /whois [-force] $nick

Takes a nick as an argument and an optional force flag. This will
print some information about the supplied user. If the force flag
is provided, the information will be refreshed from the server.

- /quote $string

Sends a string as a raw message to the server.

__/raw__ is an alias for /quote

- /t[opic] [$topic]

Takes an optional topic string. This will display the topic for the
current tab.  If a string is supplied, it will attempt to update
the channel's topic.  Only works in a channel.

- /n[ames] [-avatars]

This will print a table of all of the nicks in the current tab.  An
optional avatars flag can be provided to include avatars.

- /me $string

Sends a string as an action to the channel.

e.g. * lee hits clint with a large trout

- /w[indow] $number

Focus the provided tab number. Also accepts "next" or "prev". The
space after the w can be ommited (e.g. /w4 to focus window 4.)

- /connect $network

Connect to a network. The network must be the name of a server from
the Connections window. If you are already connected to the network
it will do nothing.

- /disconnect $network

Disconnect from a network. The network must be the name of a server
from the Connections window. This command will also stop any reconnect
timers for that network.

# NOTIFICATIONS

If you get a message with your nick in the body while no browsers
are connected, a notification will be sent using either Growl (if
running on OS X) or libnotify (on Linux.)

You can add additional patterns to highlight in the Preferences
window.

If you are using Fluid.app (a SSB for OS X) or Chrome you can also
get notifications when the window is unfocused.

# MOBILE INTERFACE

Alice has an iPhone style sheet, but it may work in other mobile
browsers as well. Any help or bug reports would be much appreciated.

# COPYRIGHT

Copyright 2010 by Lee Aylward <leedo@cpan.org>

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
