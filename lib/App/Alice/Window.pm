package App::Alice::Window;

use Encode;
use utf8;
use App::Alice::MessageBuffer;
use Text::MicroTemplate qw/encoded_string/;
use IRC::Formatting::HTML qw/irc_to_html/;
use Any::Moose;
use AnyEvent;

my $url_regex = qr/\b(https?:\/\/(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:'".,<>?«»“”‘’]))/i;

has buffer => (
  is      => 'rw',
  isa     => 'App::Alice::MessageBuffer',
  lazy    => 1,
  default => sub {
    App::Alice::MessageBuffer->new(
      id => $_[0]->id,
      store_class => $_[0]->app->config->message_store,
    );
  },
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

has _irc => (
  is       => 'ro',
  isa      => 'App::Alice::IRC',
  required => 1,
  weak_ref => 1,
);

has disabled => (
  is       => 'rw',
  isa      => 'Bool',
  default  => 0,
);

has app => (
  is      => 'ro',
  isa     => 'App::Alice',
  weak_ref => 1,
  required => 1,
);

# move irc arg to _irc, which is wrapped in a method
# because infowindow has logic to choose which irc
# connection to return
sub BUILDARGS {
  my $class = shift;
  my $args = ref $_[0] ? $_[0] : {@_};
  $args->{_irc} = $args->{irc};
  delete $args->{irc};
  return $args;
}

sub disable {
  my $self = shift;
  $self->disabled(1);
}

sub sort_name {
  my $name = lc $_[0]->title;
  $name =~ s/^[^\w\d]+//;
  $name;
}

has type => (
  is => 'ro',
  lazy => 1,
  default => sub {
    $_[0]->irc->is_channel($_[0]->title) ? "channel" : "privmsg";
  },
);

sub is_channel {$_[0]->type eq "channel"}
sub irc {$_[0]->_irc}
sub session {$_[0]->_irc->alias}

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
    session    => $self->session,
    title      => $self->title,
    is_channel => $self->is_channel,
    type       => $self->type,
    hashtag    => $self->hashtag,
    topic      => $self->topic_string,
  };
}

sub render {shift->app->render(@_)}

sub nick {
  my $self = shift;
  return $self->irc->nick;
}

sub all_nicks {
  my ($self, $modes) = @_;

  return $self->is_channel ?
         [ $self->irc->channel_nicks($self->title, $modes) ]
       : [ $self->title, $self->nick ];
}

sub join_action {
  my $self = shift;
  return {
    type      => "action",
    event     => "join",
    nicks     => $self->all_nicks,
    window    => $self->serialized,
    html => {
      window  => $self->render("window", $self),
      tab     => $self->render("tab", $self),
    },
  };
}

sub nicks_action {
  my $self = shift;
  return {
    type   => "action",
    event  => "nicks",
    nicks  => $self->all_nicks,
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
    nicks     => $self->all_nicks,
  };

  my $html = $self->render("event", $message);
  $message->{html} = $html;

  $self->buffer->add($message);
  return $message;
}

sub format_message {
  my ($self, $nick, $body) = @_;

  my $monospace = $self->app->is_monospace_nick($nick);
  # pass the inverse => italic option if this is NOT monospace
  my $html = irc_to_html($body, classes => 1, ($monospace ? () : (invert => "italic")));

  my $own_nick = $self->nick;
  my $message = {
    type      => "message",
    event     => "say",
    nick      => $nick,
    avatar    => $self->irc->nick_avatar($nick),
    window    => $self->serialized,
    html      => encoded_string($html),
    self      => $own_nick eq $nick,
    msgid     => $self->buffer->next_msgid,
    timestamp => time,
    monospaced => $monospace,
    consecutive => $nick eq $self->buffer->previous_nick,
  };

  unless ($message->{self}) {
    if ($message->{highlight} = $self->is_highlight($body)) {
      my $idle_w; $idle_w = AE::idle sub {
        undef $idle_w;
        $self->app->send_highlight($nick, $body, $self->title);
      };
    }
  }

  $message->{html} = $self->render("message", $message);

  $self->buffer->add($message);
  return $message;
}

sub format_announcement {
  my ($self, $msg) = @_;
  my $message = {
    type    => "message",
    event   => "announce",
    window  => $self->serialized,
    message => $msg,
  };
  $message->{html} = $self->render('announcement', $message);
  $message->{message} = "$message->{message}";
  $self->reset_previous_nick;
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

sub nick_table {
  my ($self, $avatars) = @_;
  if ($avatars) {
    return encoded_string($self->render("avatargrid", $self));
  }
  return _format_nick_table($self->all_nicks(1));
}

sub _format_nick_table {
  my $nicks = shift;
  return "" unless @$nicks;
  my $maxlen = 0;
  for (@$nicks) {
    my $length = length $_;
    $maxlen = $length if $length > $maxlen;
  }
  my $cols = int(74  / $maxlen + 2);
  my (@rows, @row);
  for (sort {lc $a cmp lc $b} @$nicks) {
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
  
  return "/" . $self->session . "/$path/" . $name;
}

sub is_highlight {
  my ($self, $body) = @_;
  return $self->app->is_highlight($self->nick, $body);
}

sub reply {
  my ($self, $message) = @_;
  $self->app->broadcast($self->format_announcement($message));
}

sub show {
  my ($self, $message) = @_;
  $self->app->broadcast($self->format_message($self->nick, $message));
}

__PACKAGE__->meta->make_immutable;
1;
