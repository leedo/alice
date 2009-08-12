use MooseX::ClassAttribute;
use CLASS;
use IRC::Formatting::HTML;
use Encode;
use DateTime;
use MooseX::Declare;

class Alice::Window {
  
  class_has msgid => (
    is      => 'rw',
    isa     => 'Int',
    default => 1,
  );
  
  has is_channel => (
    is      => 'ro',
    isa     => 'Bool',
    lazy    => 1,
    default => sub {
      my $self = shift;
      return $self->title =~ /^[#&]/;
    }
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
        id      => $self->id, 
        session => $self->session,
        title   => $self->title
      };
    }
  );

  method nick {
    return $self->connection->nick_name;
  }

  method topic (Str $string?) {
    if ($string) {
      $self->connection->yield(topic => $self->title, $string);
      return $string;
    }
    else {
      return $self->connection->channel_topic($self->title);
    }
  }
  
  method nextmsgid {
    return CLASS->msgid ++;
  }

  method add_message (HashRef $message) {
    push @{$self->msgbuffer}, $message;
    if (@{$self->msgbuffer} > 100) {
      shift @{$self->msgbuffer};
    }
  }

  method join_action {
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

  method timestamp {
    my $dt = DateTime->now(time_zone => "local");
    my $ampm = $dt->am_or_pm eq "AM" ? "a" : "p";
    return sprintf("%d:%02d%s",$dt->hour_12, $dt->min, $ampm);
  }

  method render_event (Str $event, Str $nick, Str $msg?) {
    $msg = decode("utf8", $msg, Encode::FB_WARN);
    my $message = {
      type      => "message",
      event     => $event,
      nick      => $nick,
      window    => $self->serialized,
      message   => $msg,
      msgid     => $self->nextmsgid,
      timestamp => $self->timestamp,
    };

    my $html = '';
    $self->tt->process("event.tt", $message, \$html);
    $message->{full_html} = $html;
    $self->add_message($message);
    return $message;
  }

  method render_message (Str $nick, Str $msg) {
    $msg = decode("utf8", $msg, Encode::FB_WARN);
    my $html = IRC::Formatting::HTML->formatted_string_to_html($msg);
    my $message = {
      type      => "message",
      event     => "say",
      nick      => $nick,
      window    => $self->serialized,
      message   => $msg,
      html      => $html,
      self      => $self->nick eq $nick,
      msgid     => $self->nextmsgid,
      timestamp => $self->timestamp,
    };
    my $fullhtml = '';
    $self->tt->process("message.tt", $message, \$fullhtml);
    $message->{full_html} = $fullhtml;
    $self->add_message($message);
    return $message;
  }

  method render_announcement (Str $msg) {
    $msg = decode("utf8", $msg, Encode::FB_WARN);
    my $message = {
      type    => "message",
      event   => "announce",
      window  => $self->serialized,
      message => $msg,
    };
    my $fullhtml = '';
    $self->tt->process('announcement.tt', $message, \$fullhtml);
    $message->{full_html} = $fullhtml;
    return $message;
  }

  method close_action {
    my $action = {
      type      => "action",
      event     => "part",
      window    => $self->serialized,
    };
    return $action;
  }

  method part {
    return unless $self->is_channel;
    $self->connection->yield("part", $self->title);
  }

  method nicks {
    return $self->connection->channel_list($self->title);
  }

  method nick_table {
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
}
