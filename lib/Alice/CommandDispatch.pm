package Alice::CommandDispatch;

use Moose;

has 'handlers' => (
  is => 'rw',
  isa => 'HashRef[Code]'
  default => sub {
    my $self = shift;
    {
      '/j(?:oin)? (.+)'     => 'join',
      '/part'             => 'part',
      '/query'            => 'query',
      '/window new (.+)'    => 'new_window',
      '/n(?:ames)?'       => 'names'
      '/topic (.+)'         => 'topic',
      '/me (.+)'            => 'me',
      '/(?:quote|raw) (.+)' => 'quote',
    }
  }
);

sub handle {
  my ($self, $command, $irc) = @_;
  if ($command =~ /^\/(.+)/) {
    $command = $1;
    for (keys %{$self->handlers}) {
      if ($command =~ /$_/) {
        print STDERR "$command $1";
      }
    }
  }
}

sub query {
  my ($self, $irc, )
}
 if ($msg =~ /^\/query (\S+)/) {
    $self->create_tab($1, $session);
  }
  elsif ($msg =~ /^\/j(?:oin)? (.+)/) {
    $irc->yield("join", $1);
  }
  elsif ($is_channel and $msg =~ /^\/part\s?(.+)?/) {
    $irc->yield("part", $1 || $chan);
  }
  elsif ($msg =~ /^\/window new (.+)/) {
    $self->create_tab($1, $session);
  }
  elsif ($is_channel and $msg =~ /^\/n(?:ames)?/ and $chan) {
    $self->show_nicks($chan, $session);
  }
  elsif ($is_channel and $msg =~ /^\/topic\s?(.+)?/) {
    if ($1) {
      $irc->yield("topic", $chan, $1);
    }
    else {
      my $topic = $irc->channel_topic($chan);
      $self->send_topic(
        $topic->{SetBy}, $chan, $session, decode_utf8($topic->{Value})
      );
    }
  }
  elsif ($msg =~ /^\/me (.+)/) {
    my $nick = $irc->nick_name;
    $self->display_message($nick, $chan, $session, decode_utf8("• $1"));
    $irc->yield("ctcp", $chan, "ACTION $1");
  }
  elsif ($msg =~ /^\/(?:quote|raw) (.+)/) {
    $irc->yield("quote", $1);
  }
  elsif ($msg =~ /^\/(.+?)(?:\s|$)/) {
    $self->display_announcement($chan, $session, "Invalid command $1");
  }
  else {
    $self->log_debug("sending message to $chan");
    my $nick = $irc->nick_name;
    $self->display_message($nick, $chan, $session, decode_utf8($msg));
    $irc->yield("privmsg", $chan, $msg);
  }