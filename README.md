# NAME

App::Alice - an Altogether Lovely Internet Chatting Experience

# SYNPOSIS

  arthur:~ leedo$ alice
  Location: http://localhost:8080/

# DESCRIPTION

Alice is an IRC client that can be run either locally or remotely, and 
can be viewed in any WebKit browser. The alice server maintains a message 
buffer, so when a browser connects it is sent the 100 most recent lines 
from each channel. This allows the user to close their browser while alice 
continues to aggregate messages.

Alice's built in web server maintains a long streaming HTTP connection to 
each browser, and uses this connection to instantly push messages to the 
browsers. Sending messages or commands is done through an HTTP request 
back to alice's HTTP server.

Alice also logs messages to an SQLite database. These logs are searchable 
by selecting Logs from the gear menu in the bottom corner.

# USAGE

After installing, there will be a new `alice' command available. Run this 
command to start the alice server. Open your browser (Safari, Chrome, or 
Fluid) and connect to the URL that was printed to your terminal (likely 
http://localhost:8080/). You will see a small gear icon in the bottom 
corner; this button will bring up the connection configuration menu. Add 
one or more IRC servers and channels in this window and save. Alice will 
then connect to those servers, and the channels will appear as tabs at 
the bottom of the screen.

# COMMANDS

## /j[oin] [-network] $channel

Takes a channel name as an argument. It will attempt to join this channel
on the server of the channel that you typed the command into.

## /close

Closes the current tab, even private message tabs. If used in a channel
it will also part the channel.

## /clear

This will clear the current tab's messages from your browser. It will also 
clear the tab's message buffer so when you refresh your browser the messages 
won't re-appear (as they normally would.)

## /msg [-network] $nick [$msg]

Takes a nick as an argument. This will open a new tab for private messaging
with a user. Only works in a channel.

## /whois $nick

Takes a nick as an argument. This will print some information about the
supplied user.

## /quote $string

Sends a string as a raw message to the server.

## /topic [$topic]

Takes an optional topic string. This will display the topic for the current tab.
If a string is supplied, it will attempt to update the channel's topic.
Only works in a channel.

## /n[ames]

This will print all of the nick's in the current tab in a tabular format.

## /me $string

Sends a string as an ACTION to the channel

# NOTIFICATIONS

If you get a message with your nick in the body, while no browsers are
connected, a notification will be sent to either Growl (if running on
OS X) or using libnotify (on Linux.) Alice does not send any notifications
if a browser is connected (the exception being Fluid SSB which will
Growl if unfocused). This is something that will probably become 
configurable over time.

# MOBILE INTERFACE

Alice has an iphone style sheet, but it may work well in other mobile browsers
as well. Any reports would be much appreciated.

# COPYRIGHT

Copyright 2010 by Lee Aylward <leedo@cpan.org>

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.