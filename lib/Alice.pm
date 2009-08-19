use MooseX::Declare;

class Alice {
  use Alice::Window;
  use Alice::HTTPD;
  use Alice::IRC;
  use MooseX::AttributeHelpers;
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
    metaclass => 'Collection::Hash',
    isa       => 'HashRef[Alice::Window]',
    default   => sub {{}},
    provides  => {
      values => 'windows',
      set    => 'add_window',
      exists => 'has_window',
      get    => 'get_window',
      delete => 'remove_window',
      keys   => 'window_ids',
    }
  );
  
  method nick_windows (Str $nick) {
    return grep {$_->includes_nick($nick)} $self->windows;
  }

  method buffered_messages (Int $min) {
    return [ grep {$_->{msgid} > $min} map {@{$_->msgbuffer}} $self->windows ];
  }

  method connections {
    return map {$_->connection} values %{$self->ircs};
  }

  method find_or_create_window (Str $title, $connection) {
    my $id = "win_" . crc16(lc($title . $connection->session_alias));
    if (my $window = $self->get_window($id)) {
      return $window;
    }
    my $window = Alice::Window->new(
      title      => $title,
      connection => $connection
    );  
    $self->add_window($id, $window);
  }

  method close_window (Alice::Window $window) {
    return unless $window;
    $self->send($window->close_action);
    $self->log_debug("sending a request to close a tab: " . $window->title)
      if $self->httpd->has_clients;
    $self->remove_window($window->id);
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
