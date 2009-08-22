use MooseX::Declare;

class App::Alice::Window {
  use Encode;
  use DateTime;
  use Digest::CRC qw/crc16/;
  use MooseX::ClassAttribute;
  use MooseX::AttributeHelpers;
  use IRC::Formatting::HTML;
  
  class_has msgid => (
    metaclass => 'Counter',
    is        => 'rw',
    isa       => 'Int',
    default   => sub {1},
    provides  => {
      inc => 'next_msgid',
    }
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
    is       => 'ro',
    isa      => 'POE::Component::IRC::State',
    required => 1,
  );
  
  has nicks => (
    metaclass => 'Collection::Hash',
    isa       => 'HashRef[Str|Undef]',
    default   => sub {{}},
    provides  => {
      delete   => 'remove_nick',
      exists   => 'includes_nick',
      get      => 'nick_info',
      keys     => 'all_nicks',
      kv       => 'all_nick_info',
      set      => 'add_nick',
    }
  );
  
  has 'tt' => (
    is       => 'ro',
    isa      => 'Template',
    required => 1,
  );
  
  method rename_nick (Str $nick, Str $new_nick) {
    return unless $self->includes_nick($nick);
    my $info = $self->nick_info($nick);
    $self->add_nick($new_nick, $info);
    $self->remove_nick($nick);
  }

  method serialized (Bool :$encoded = 0) {
    return {
      id         => $self->id, 
      session    => $self->session,
      title      => $encoded ? encode('utf8', $self->title) : $self->title,
      is_channel => $self->is_channel,
    };
  }

  method nick {
    return $self->connection->nick_name;
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
      nicks     => [ $self->all_nicks ],
      window    => $self->serialized,
    };
  }

  method clear_action {
    return {
      type      => "action",
      event     => "clear",
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
      msgid     => $self->next_msgid,
      timestamp => $self->timestamp,
      nicks     => [ $self->all_nicks ],
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
      msgid     => $self->next_msgid,
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

  method whois_table (Str $nick) {
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
}
