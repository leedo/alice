package App::Alice::Window;

use Encode;
use utf8;
use App::Alice::MessageBuffer;
use Text::MicroTemplate qw/encoded_string/;
use IRC::Formatting::HTML qw/irc_to_html/;
use Any::Moose;

my $url_regex = qr/\b(https?:\/\/(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:'".,<>?«»“”‘’]))/i;

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

has buffer => (
  is      => 'rw',
  isa     => 'App::Alice::MessageBuffer',
  lazy    => 1,
  default => sub {
    my $self = shift;
    App::Alice::MessageBuffer->new(
      store_class => $self->app->config->message_store,
      id          => $self->id,
    );
  },
);

has title => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has sort_name => (
  is       => 'ro',
  lazy     => 1,
  default  => sub {
    my $name = $_[0]->title;
    $name =~ s/^#//;
    $name;
  }
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
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub {
    return $_[0]->app->_build_window_id($_[0]->title, $_[0]->session);
  },
);

has session => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub {return shift->irc->alias}
);

has _irc => (
  is       => 'ro',
  isa      => 'App::Alice::IRC',
  required => 1,
  weak_ref => 1,
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

sub irc { $_[0]->_irc }

sub serialized {
  my ($self) = @_;
  return {
    id         => $self->id, 
    session    => $self->session,
    title      => $self->title,
    is_channel => $self->is_channel,
    type       => $self->type,
    hashtag    => $self->hashtag,
  };
}

sub nick {
  my $self = shift;
  decode_utf8($self->irc->nick) unless utf8::is_utf8($self->irc->nick);
}

sub all_nicks {
  my $self = shift;
  return [] if $self->type eq "info";

  if ($self->is_channel) {
    return $self->irc->channel_nicks($self->title);
  } else {
    return [$self->title, $self->nick];
  }
}

sub join_action {
  my $self = shift;
  my $action = {
    type      => "action",
    event     => "join",
    nicks     => $self->all_nicks,
    window    => $self->serialized,
  };
  $action->{html}{window} = $self->app->render("window", $self);
  $action->{html}{tab} = $self->app->render("tab", $self);
  $action->{html}{select} = $self->app->render("select", $self);
  return $action;
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
    msgid     => $self->app->next_msgid,
    timestamp => time,
    nicks     => $self->all_nicks,
  };
  $message->{html} = make_links_clickable(
    $self->app->render("event", $message)
  );
  $self->buffer->add($message);
  return $message;
}

sub format_message {
  my ($self, $nick, $body) = @_;
  $body = decode_utf8($body) unless utf8::is_utf8($body);

  my $monospace = $self->app->is_monospace_nick($nick);
  # pass the inverse => italic option if this is NOT monospace
  my $html = irc_to_html($body, ($monospace ? () : (invert => "italic")));

  $html = make_links_clickable($html);
  my $own_nick = $self->nick;
  my $message = {
    type      => "message",
    event     => "say",
    nick      => $nick,
    avatar    => $self->irc->nick_avatar($nick),
    window    => $self->serialized,
    html      => encoded_string($html),
    self      => $own_nick eq $nick,
    msgid     => $self->app->next_msgid,
    timestamp => time,
    monospaced => $monospace,
    consecutive => $nick eq $self->buffer->previous_nick ? 1 : 0,
  };
  unless ($message->{self}) {
    $message->{highlight} = $self->app->is_highlight($own_nick, $body);
  }
  $message->{html} = $self->app->render("message", $message);
  $self->buffer->add($message);
  return $message;
}

sub format_announcement {
  my ($self, $msg) = @_;
  $msg = decode_utf8($msg) unless utf8::is_utf8($msg)
          or ref $msg eq "Text::MicroTemplate::EncodedString";
  my $message = {
    type    => "message",
    event   => "announce",
    window  => $self->serialized,
    message => $msg,
  };
  $message->{html} = $self->app->render('announcement', $message);
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
    return encoded_string($self->app->render("avatargrid", $self));
  }
  return _format_nick_table($self->all_nicks);
}

sub make_links_clickable {
  my $html = shift;
  $html =~ s/$url_regex/<a href="$1" target="_blank" rel="noreferrer">$1<\/a>/gi;
  return $html;
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
  if ($self->type eq "info") {
    return "/" . $self->title;
  }
  return "/" . $self->session . "/" . $self->title;
}

__PACKAGE__->meta->make_immutable;
1;
