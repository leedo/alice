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

sub sort_name {
  my $name = $_[0]->title;
  $name =~ s/^#//;
  $name;
}

sub type {
  return $_[0]->title =~ /^[#&]/ ? "channel" : "privmsg";
}

sub is_channel {$_[0]->type eq "channel"}
sub irc {$_[0]->_irc}
sub session {$_[0]->_irc->alias}

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

sub render {shift->app->render(@_)}

sub nick {
  my $self = shift;
  decode_utf8($self->irc->nick) unless utf8::is_utf8($self->irc->nick);
}

sub all_nicks {
  my $self = shift;

  return $self->is_channel ?
         [ $self->irc->channel_nicks($self->title) ]
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
      select  => $self->render("select", $self),
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
    msgid     => $self->app->next_msgid,
    timestamp => time,
    nicks     => $self->all_nicks,
  };

  my $html = $self->render("event", $message);
  make_links_clickable(\$html);
  $message->{html} = $html;

  $self->buffer->add($message);
  return $message;
}

sub format_message {
  my ($self, $nick, $body) = @_;
  $body = decode_utf8($body) unless utf8::is_utf8($body);

  my $monospace = $self->app->is_monospace_nick($nick);
  # pass the inverse => italic option if this is NOT monospace
  my $html = irc_to_html($body, classes => 1, ($monospace ? () : (invert => "italic")));
  make_links_clickable(\$html);

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
  $message->{html} = $self->render("message", $message);

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
  return _format_nick_table($self->all_nicks);
}

sub make_links_clickable {
  my $html = shift;
  $$html =~ s/$url_regex/<a href="$1" target="_blank" rel="noreferrer">$1<\/a>/gi;
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
