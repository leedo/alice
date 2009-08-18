use MooseX::Declare;

class Alice {
  use Alice::Window;
  use Alice::HTTPD;
  use Alice::IRC;
  use Digest::CRC qw/crc16/;
  use POE;

  has config => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
  );

  has ircs => (
    is      => 'ro',
    isa     => 'HashRef[HashRef]',
    default => sub {{}},
  );

  has httpd => (
    is      => 'ro',
    isa     => 'Alice::HTTPD',
    lazy    => 1,
    default => sub {
      Alice::HTTPD->new(app => shift);
    },
  );

  has dispatcher => (
    is      => 'ro',
    isa     => 'Alice::CommandDispatch',
    default => sub {
      Alice::CommandDispatch->new(app => shift);
    }
  );

  has notifier => (
    is      => 'ro',
    default => sub {
      eval {
        if ($^O eq 'darwin') {
          require Alice::Notifier::Growl;
          Alice::Notifier::Growl->new;
        }
        elsif ($^O eq 'linux') {
          require Alice::Notifier::LibNotify;
          Alice::Notifier::LibNotify->new;
        }
      }
    }
  );

  method dispatch (Str $command, Alice::Window $window) {
    $self->dispatcher->handle($command, $window);
  }

  has window_map => (
    is      => 'rw',
    isa     => 'HashRef[Alice::Window]',
    default => sub {{}},
  );

  method windows {
    return values %{$self->window_map};
  }

  method buffered_messages (Int $min) {
    return [ grep {$_->{msgid} > $min} map {@{$_->msgbuffer}} $self->windows ];
  }

  method connections {
    return map {$_->connection} values %{$self->ircs};
  }

  method window (Str $session, Str $title) {
    my $id = "win_" . crc16(lc($title . $session));
    return $self->window_map->{$id};
  }

  method add_window (Alice::Window $window) {
    $self->window_map->{$window->id} = $window;
  }

  method create_window (Str $title, $connection) {
    my $window = Alice::Window->new(
      title      => $title,
      connection => $connection,
    );
    $self->add_window($window);
    $self->send($window->join_action);
    $self->log_debug("sending a request for a new tab: " . $window->title)
      if $self->httpd->has_clients;
    return $window;
  }

  method close_window (Alice::Window $window) {
    return unless $window;
    $self->send($window->close_action);
    $self->log_debug("sending a request to close a tab: " . $window->title)
      if $self->httpd->has_clients;
    delete $self->window_map->{$window->id};
  }

  method add_irc_server (Str $name, HashRef $config) {
    $self->ircs->{$name} = Alice::IRC->new(
      app    => $self,
      alias  => $name,
      config => $config
    );
  }

  method run {
    $self->httpd;
    $self->add_irc_server($_, $self->config->{servers}{$_})
      for keys %{$self->config->{servers}};
    POE::Kernel->run;
  }

  sub send {
    my ($self, @messages) = @_;
    $self->httpd->send(@messages);
    return unless $self->notifier and ! $self->httpd->has_clients;
    for my $message (@messages) {
      $self->notifier->display($message) if $message->{highlight};
    }
  }

  sub log_debug {
    shift;
    print STDERR join(" ", @_) . "\n";
  }
}
