package Alice::Window;

use Encode;
use utf8;
use Alice::MessageBuffer;
use Text::MicroTemplate qw/encoded_string/;
use IRC::Formatting::HTML qw/irc_to_html/;
use Any::Moose;
use AnyEvent;

my $url_regex = qr/\b(https?:\/\/(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:'".,<>?«»“”‘’]))/i;

has buffer => (
  is       => 'rw',
  required => 1,
);

has title => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has topic => (
  is      => 'rw',
  isa     => 'HashRef[Str|Undef]',
  default => sub {{
    string => 'no topic set',
    author => '',
    time   => time,
  }}
);

has id => (
  is       => 'ro',
  required => 1,
);

has disabled => (
  is       => 'rw',
  default  => 0,
);

has render => (
  is       => 'ro',
  required => 1,
);

sub sort_name {
  my $name = lc $_[0]->title;
  $name =~ s/^[^\w\d]+//;
  $name;
}

sub pretty_name {
  my $self = shift;
  if ($self->is_channel) {
    return substr $self->title, 1;
  }
  return $self->title;
}

has type => (
  is => 'ro',
  required => 1,
);

has network => (
  is => 'ro',
  required => 1,
);

sub is_channel {$_[0]->type eq "channel"}

sub topic_string {
  my $self = shift;
  if ($self->is_channel) {
    return $self->topic->{string} || $self->title . ": no topic set";
  }
  return $self->title;
}

sub serialized {
  my ($self) = @_;
  return {
    id         => $self->id, 
    network    => $self->network,
    title      => $self->title,
    is_channel => $self->is_channel,
    type       => $self->type,
    hashtag    => $self->hashtag,
    topic      => $self->topic_string,
  };
}

sub join_action {
  my $self = shift;
  return {
    type      => "action",
    event     => "join",
    window    => $self->serialized,
    html => {
      window  => $self->render->("window", $self),
      tab     => $self->render->("tab", $self),
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
    msgid     => $self->buffer->next_msgid,
    timestamp => time,
  };

  my $html = $self->render->("event", $message);
  $message->{html} = $html;

  $self->buffer->add($message);
  return $message;
}

sub format_topic {
  my $self = shift;
  return $self->format_event("topic", $self->topic->{author} || "", $self->topic_string);
}

sub format_message {
  my ($self, $nick, $body, %options) = @_;

  # pass the inverse => italic option if this is NOT monospace
  my $html = irc_to_html($body, classes => 1, ($options{monospaced} ? () : (invert => "italic")));

  my $message = {
    type      => "message",
    event     => "say",
    nick      => $nick,
    window    => $self->serialized,
    html      => encoded_string($html),
    msgid     => $self->buffer->next_msgid,
    timestamp => time,
    consecutive => $nick eq $self->buffer->previous_nick,
    %options,
  };

  $message->{html} = $self->render->("message", $message);

  $self->buffer->add($message);
  return $message;
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

sub reset_previous_nick {
  my $self = shift;
  $self->buffer->previous_nick("");
}

sub previous_nick {
  my $self = shift;
  return $self->buffer->previous_nick;
}

sub hashtag {
  my $self = shift;

  my $name = $self->title;
  $name =~ s/[#&~@]//g;
  my $path = $self->type eq "privmsg" ? "users" : "channels";
  
  return "/" . $self->network . "/$path/" . $name;
}

__PACKAGE__->meta->make_immutable;
1;
