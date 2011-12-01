package Alice::Window;

use strict;
use warnings;

use Encode;
use Text::MicroTemplate qw/encoded_string/;
use IRC::Formatting::HTML qw/irc_to_html/;
use Plack::Util::Accessor qw/title type id network previous_nick disabled topic/;
use AnyEvent;

sub new {
  my ($class, %args) = @_;
  for (qw/title type id network render msg_iter/) {
    die "$_ is required" unless defined $args{$_};
  }

  $args{topic} = {
    string => "no topic set",
    author => "",
  };

  $args{disbled} = 0;
  $args{previous_nick} = "";

  bless \%args, __PACKAGE__;
}

sub sort_name {
  my $name = lc $_[0]->{title};
  $name =~ s/^[^\w\d]+//;
  $name;
}

sub pretty_name {
  my $self = shift;
  if ($self->{type} eq "channel") {
    return substr $self->{title}, 1;
  }
  return $self->{title};
}

sub is_channel {
  $_[0]->{type} eq "channel"
}

sub topic_string {
  my $self = shift;
  if ($self->{type} eq "channel") {
    return $self->{topic}{string} or "$self->{title}: no topic set";
  }
  return $self->{title};
}

sub serialized {
  my ($self) = @_;

  return {
    is_channel => $self->is_channel,
    hashtag    => $self->hashtag,
    topic      => $self->topic_string,
    map {$_ => $self->{$_}} qw/id network title type/
  };
}

sub join_action {
  my $self = shift;
  return {
    type      => "action",
    event     => "join",
    window    => $self->serialized,
    html => {
      window  => $self->{render}->("window", $self),
      tab     => $self->{render}->("tab", $self),
    },
  };
}

sub nicks_action {
  my ($self, @nicks) = @_;
  return {
    type   => "action",
    event  => "nicks",
    nicks  => \@nicks,
    window => $self->serialized,
  };
}

sub clear_action {
  my $self = shift;
  return {
    type   => "action",
    event  => "clear",
    window => $self->serialized,
  };
}

sub format_event {
  my ($self, $event, $nick, $body) = @_;
  my $message = {
    type      => "message",
    event     => $event,
    nick      => $nick,
    window    => $self->serialized,
    body      => $body,
    timestamp => time,
  };

  $self->{previous_nick} = "";

  $self->{msg_iter}->(sub {
    $message->{msgid} = shift;
    $message->{html} = $self->{render}->("event", $message);
    return $message;
  });
}

sub format_message {
  my ($self, $nick, $body, %options) = @_;
  my $html = irc_to_html($body, classes => 1, ($options{monospaced} ? () : (invert => "italic")));
  my $message = {
    type      => "message",
    event     => "say",
    nick      => $nick,
    window    => $self->serialized,
    html      => encoded_string($html),
    timestamp => time,
    consecutive => $nick eq $self->{previous_nick},
    %options,
  };

  $self->{previous_nick} = $nick;

  $self->{msg_iter}->(sub {
    $message->{msgid} = shift;
    $message->{html} = $self->{render}->("message", $message);
    return $message;
  });
}

sub close_action {
  my $self = shift;
  return +{
    type   => "action",
    event  => "part",
    window => $self->serialized,
  };
}

sub trim_action {
  my ($self, $lines) = @_;
  return +{
    type => "action",
    event => "trim",
    lines => $lines,
    window => $self->serialized,
  };
}

sub nick_table {
  my ($self, @nicks) = @_;

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

sub hashtag {
  my $self = shift;

  my $name = $self->title;
  $name =~ s/[#&~@]//g;
  my $path = $self->type eq "privmsg" ? "users" : "channels";
  
  return "/" . $self->{network} . "/$path/" . $name;
}

1;
