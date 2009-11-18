package App::Alice::Window;

use Moose;
use Encode;
use Digest::CRC qw/crc16/;
use MooseX::ClassAttribute;
use IRC::Formatting::HTML;

class_has msgid => (
  traits    => ['Counter'],
  is        => 'rw',
  isa       => 'Int',
  default   => 1,
  handles   => {next_msgid => 'inc'}
);

has type => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub {return shift->title =~ /^[#&]/ ? "channel" : "privmsg"}
);

has is_channel => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub {return shift->type eq "channel"}
);

has assetdir => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has msgbuffer => (
  is      => 'rw',
  isa     => 'ArrayRef',
  default => sub {[]},
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

has buffersize => (
  is      => 'ro',
  isa     => 'Int',
  default => 100,
);

has id => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub {return "win_" . crc16(lc($_[0]->title . $_[0]->session))}
);

has session => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub {return shift->irc->alias}
);

has irc => (
  is       => 'ro',
  isa      => 'App::Alice::IRC',
  required => 1,
);

has app => (
  is      => 'ro',
  isa     => 'App::Alice',
  required => 1,
);

sub BUILD {
  shift->meta->error_class('Moose::Error::Croak');
}

sub serialized {
  my ($self, $encoded) = @_;
  $encoded = 0 unless $encoded;
  return {
    id         => $self->id, 
    session    => $self->session,
    title      => $encoded ? encode('utf8', $self->title) : $self->title,
    is_channel => $self->is_channel,
    type       => $self->type,
  };
}

sub nick {
  my $self = shift;
  return $self->irc->nick;
}

sub all_nicks {
  my $self = shift;
  return unless $self->is_channel;
  return $self->irc->channel_nicks($self->title);
}

sub add_message {
  my ($self, $message) = @_;
  push @{$self->msgbuffer}, $message;
  if (@{$self->msgbuffer} > $self->buffersize) {
    shift @{$self->msgbuffer};
  }
}

sub clear_buffer {
  my $self = shift;
  $self->msgbuffer([]);
}

sub join_action {
  my $self = shift;
  my $action = {
    type      => "action",
    event     => "join",
    window    => $self->serialized,
  };
  $action->{html}{window} = $self->app->render("window", 0, $self);
  $action->{html}{tab} = $self->app->render("tab", 0, $self);
  return $action;
}

sub nicks_action {
  my $self = shift;
  return {
    type   => "action",
    event  => "nicks",
    nicks  => [ $self->all_nicks ],
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

sub timestamp {
  my $self = shift;
  my @time = localtime(time);
  my $hour = $time[2];
  my $ampm = $hour > 11 ? 'p' : 'a';
  $hour = $hour > 12 ? $hour - 12 : $hour;
  return sprintf("%d:%02d%s",$hour, $time[1], $ampm);
}

sub format_event {
  my ($self, $event, $nick, $body) = @_;
  $body = decode("utf8", $body, Encode::FB_WARN);
  my $message = {
    type      => "message",
    event     => $event,
    nick      => $nick,
    window    => $self->serialized,
    body      => $body,
    msgid     => $self->next_msgid,
    timestamp => $self->timestamp,
    nicks     => [ $self->all_nicks ],
  };
  $message->{full_html} = $self->app->render("event", $message);
  $self->add_message($message);
  return $message;
}

sub format_message {
  my ($self, $nick, $body) = @_;
  $body = decode("utf8", $body, Encode::FB_WARN);
  my $html = IRC::Formatting::HTML->formatted_string_to_html($body);
  my $own_nick = $self->nick;
  my $message = {
    type      => "message",
    event     => "say",
    nick      => $nick,
    avatar    => $self->irc->nick_avatar($nick),
    window    => $self->serialized,
    body      => $body,
    highlight => $body =~ /\b$own_nick\b/i ? 1 : 0,
    html      => $html,
    self      => $own_nick eq $nick,
    msgid     => $self->next_msgid,
    timestamp => $self->timestamp,
  };
  $message->{full_html} = $self->app->render("message", $message);
  $self->add_message($message);
  return $message;
}

sub format_announcement {
  my ($self, $msg) = @_;
  $msg = decode("utf8", $msg, Encode::FB_WARN);
  my $message = {
    type    => "message",
    event   => "announce",
    window  => $self->serialized,
    message => $msg,
  };
  $message->{full_html} = $self->app->render('announcement', $message);
  return $message;
}

sub close_action {
  my $self = shift;
  my $action = {
    type   => "action",
    event  => "part",
    window => $self->serialized,
  };
  return $action;
}

sub part {
  my $self = shift;
  return unless $self->is_channel;
  $self->irc->cl->send_srv(PART => $self->title);
}

sub set_topic {
  my ($self, $topic) = @_;
  $self->topic({
    string => $topic,
    author => $self->nick,
    time   => time,
  });
  $self->irc->cl->send_srv(TOPIC => $self->title, $topic);
}

sub nick_table {
  my $self = shift;
  return _format_nick_table($self->all_nicks);
}

sub _format_nick_table {
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

__PACKAGE__->meta->make_immutable;
1;
