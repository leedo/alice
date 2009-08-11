package Alice::Window;

use Moose;
use IRC::Formatting::HTML;

has is_channel => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub {
    my $self = shift;
    return $self->title =~ /^[#&]/;
  }
);

has title => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has id => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub {
    my $self = shift;
    my $id = $self->title . $self->session;
    $id =~ s/^[#&]/chan_/;
    return $id;
  }
);

has session => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub {
    my $self = shift;
    return $self->connection->session_alias;
  }
);

has connection => (
  is => 'ro',
  isa => 'POE::Component::IRC::State',
  required => 1,
);

sub nick {
  my $self = shift;
  return $self->connection->nick_name;
}

sub topic {
  my ($self, $string) = @_;
  if ($string) {
    $self->connection->yield(topic => $self->title, $string);
    return $string;
  }
  else {
    return $self->connection->channel_topic($self->title);
  }
}

has msgbuffer => (
  is      => 'rw',
  isa     => 'ArrayRef',
  default => sub {[]},
);

sub add_message {
  my ($self, $message) = shift;
  push @{$self->msgbuffer}, $message;
  if (@{$self->msgbuffer} > 100) {
    shift @{$self->msgbuffer};
  }
}

has 'tt' => (
  is     => 'ro',
  isa    => 'Template',
  default => sub {
    Template->new(
      INCLUDE_PATH => 'data/templates',
      ENCODING     => 'UTF8'
    );
  },
);

has 'serialized' => (
  is      => 'ro',
  isa     => 'HashRef',
  lazy    => 1,
  default => sub {
    my $self = shift;
    return {
      id     => $self->id, 
      ession => $self->session,
      title  => $self->title
    };
  }
);

sub join_action {
  my $self = shift;
  my $action = {
    type      => "action",
    event     => "join",
    window    => $self->serialized,
  };

  my $window_html = '';
  $self->tt->process("window.tt", $action, \$window_html);
  $action->{html}{window} = $window_html;
  my $tab_html = '';
  $self->tt->process("tab.tt", $action, \$tab_html);
  $action->{html}{tab} = $tab_html;
  return $action;
}

sub render_event {
  my ($self, $event, $nick, $str) = @_;
  my $message = {
    type      => "message",
    event     => $event,
    nick      => $nick,
    window    => $self->serialized,
    message   => $str,
  };

  my $html = '';
  $self->tt->process("event.tt", $message, \$html);
  $message->{full_html} = $html;
  $self->add_message($message);
  return $message;
}

sub render_message {
  my ($self, $nick, $str) = @_;
  my $html = IRC::Formatting::HTML->formatted_string_to_html($str);
  my $message = {
    type      => "message",
    event     => "say",
    nick      => $nick,
    window    => $self->serialized,
    message   => $str,
    html      => $html,
    self      => $self->nick eq $nick,
  };
  my $fullhtml = '';
  $self->tt->process("message.tt", $message, \$fullhtml);
  $message->{full_html} = $fullhtml;
  $self->add_message($message);
  return $message;
}

sub render_announcement {
  my ($self, $str) = @_;
  my $message = {
    type    => "message",
    event   => "announce",
    window  => $self->serialized,
    message => $str,
  };
  my $fullhtml = '';
  $self->tt->process('announcement.tt', $message, \$fullhtml);
  $message->{full_html} = $fullhtml;
  return $message;
}

sub close_action {
  my $self = shift;
  my $action = {
    type      => "action",
    event     => "part",
    window    => $self->serialized,
  };
  return $action;
}

sub part {
  my $self = shift;
  return unless $self->is_channel;
  $self->connection->yield("part", $self->title);
}

sub nicks {
  my $self = shift;
  return $self->connection->channel_list($self->title);
}

sub nick_table {
  my $self = shift;
  return _format_nick_table($self->nicks);
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
no Moose;
1;