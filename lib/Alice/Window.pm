use MooseX::Declare;

class Alice::Window {
  
  use CLASS;
  use Encode;
  use DateTime;
  use Digest::CRC qw/crc16/;
  use MooseX::ClassAttribute;
  use IRC::Formatting::HTML;
  
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
      return "win_" . crc16(lc($self->title . $self->session));
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
  
  has nick_stash => (
    is => 'rw',
    isa => 'ArrayRef[Str]',
    default => sub {[]}
  );
  
  has nick_map => (
    is => 'rw',
    isa => 'HashRef[Str]',
    default => sub {[]}
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
  
  method nicks {
    if ($self->connection->is_chan_synced($self->title)) {
      return [ $self->connection->channel_list($self->title) ];
    }
    return [ keys %{$self->nick_map} ];
  }

  method serialized (Bool :$encoded = 0) {
    return {
      id      => $self->id, 
      session => $self->session,
      title   => $encoded ? encode('utf8', $self->title) : $self->title,
    };
  }

  method nick {
    return $self->connection->nick_name;
  }
  
  method stash_nicks (ArrayRef $nicks) {
    push @{$self->nick_stash}, @$nicks;
  }
  
  method finalize_nicks {
    # we can store more nick info in this hash later
    $self->nicks({ map {$_ => $_} @{$self->nick_stash} });
  }

  method topic (Str $string?) {
    if ($string) {
      $string = decode("utf8", $string, Encode::FB_WARN);
      $self->connection->yield(topic => $self->title, $string);
      return $string;
    }
    else {
      return $self->connection->channel_topic($self->title) || {};
    }
  }
  
  method nextmsgid {
    return CLASS->msgid(CLASS->msgid + 1);
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
  
  method nicks_action {
    return {
      type      => "action",
      event     => "nicks",
      nicks     => $self->nicks,
      window    => $self->serialized,
    };
  }

  method timestamp {
    my $dt = DateTime->now(time_zone => "local");
    my $ampm = $dt->am_or_pm eq "AM" ? "a" : "p";
    return sprintf("%d:%02d%s",$dt->hour_12, $dt->min, $ampm);
  }

  method render_event (Str $event, Str $nick, Str $body?) {
    $body = decode("utf8", $body, Encode::FB_WARN);
    my $message = {
      type      => "message",
      event     => $event,
      nick      => $nick,
      window    => $self->serialized,
      body      => $body,
      msgid     => $self->nextmsgid,
      timestamp => $self->timestamp,
      nicks     => $self->nicks,
    };

    my $html = '';
    $self->tt->process("event.tt", $message, \$html);
    $message->{full_html} = $html;
    $self->add_message($message);
    return $message;
  }

  method render_message (Str $nick, Str $body) {
    $body = decode("utf8", $body, Encode::FB_WARN);
    my $html = IRC::Formatting::HTML->formatted_string_to_html($body);
    my $own_nick = $self->nick;
    my $message = {
      type      => "message",
      event     => "say",
      nick      => $nick,
      window    => $self->serialized,
      body      => $body,
      highlight => $body =~ /\b$own_nick\b/i ? 1 : 0,
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

  method nick_info (Str $nick) {
    my $info = $self->connection->nick_info($nick);
    if ($info) {
      return join "\n", (
        map({"$_: $info->{$_}"} keys %$info),
        "Channels: " . join " ", $self->connection->nick_channels($nick)
      );
    }
    return "No info for user \"$nick\"";
  }

  method nick_table {
    return _format_nick_table(@{$self->nicks});
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
