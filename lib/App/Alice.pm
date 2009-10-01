use MooseX::Declare;

class App::Alice {
  use feature ':5.10';
  use App::Alice::Window;
  use App::Alice::InfoWindow;
  use App::Alice::HTTPD;
  use App::Alice::IRC;
  use App::Alice::Signal;
  use App::Alice::Config;
  use Digest::CRC qw/crc16/;
  use Encode;

  our $VERSION = '0.01';

  has config => (
    is       => 'ro',
    isa      => 'App::Alice::Config',
    default  => sub {App::Alice::Config->new},
  );

  has ircs => (
    is      => 'ro',
    isa     => 'HashRef[HashRef]',
    default => sub {{}},
  );

  has httpd => (
    is      => 'ro',
    isa     => 'App::Alice::HTTPD',
    lazy    => 1,
    default => sub {
      App::Alice::HTTPD->new(app => shift);
    },
  );

  has dispatcher => (
    is      => 'ro',
    isa     => 'App::Alice::CommandDispatch',
    default => sub {
      App::Alice::CommandDispatch->new(app => shift);
    }
  );

  has notifier => (
    is      => 'ro',
    default => sub {
      eval {
        given ($^O) {
          when ('darwin') {
            require App::Alice::Notifier::Growl;
            return App::Alice::Notifier::Growl->new;
          }
          when ('linux') {
            require App::Alice::Notifier::LibNotify;
            return App::Alice::Notifier::LibNotify->new;
          }
        }
      }
    }
  );

  has window_map => (
    traits    => ['Hash'],
    isa       => 'HashRef[App::Alice::Window|App::Alice::InfoWindow]',
    default   => sub {{}},
    handles   => {
      windows       => 'values',
      add_window    => 'set',
      has_window    => 'exists',
      get_window    => 'get',
      remove_window => 'delete',
      window_ids    => 'keys',
    }
  );
  
  has 'tt' => (
    is => 'ro',
    isa => 'Template',
    lazy => 1,
    default => sub {
      my $self = shift;
      Template->new(
        INCLUDE_PATH => $self->config->assetdir . '/templates',
        ENCODING     => 'UTF8'
      );
    },
  );
  
  has 'info_window' => (
    is => 'ro',
    isa => 'App::Alice::InfoWindow',
    lazy => 1,
    default => sub {
      my $self = shift;
      my $info = App::Alice::InfoWindow->new(
        assetdir => $self->config->assetdir,
        tt       => $self->tt,
      );
      $self->add_window($info->title, $info);
      return $info;
    }
  );
  
  sub BUILD {
    my $self = shift;
    $self->meta->error_class('Moose::Error::Croak');
    $SIG{INT} = sub {App::Alice::Signal->new(app => $self, type => "INT")};
    $SIG{QUIT} = sub {App::Alice::Signal->new(app => $self, type => "QUIT")};
  }
  
  method run {
    # initialize tt and httpd because they are lazy
    $self->tt;
    $self->httpd;
    
    say STDERR "You can view your IRC session at: http://localhost:"
                 . $self->config->port."/view";

    $self->add_irc_server($_, $self->config->servers->{$_})
      for keys %{$self->config->servers};

    POE::Kernel->run;
  }
  
  method dispatch (Str $command, App::Alice::Window $window) {
    $self->dispatcher->handle($command, $window);
  }
  
  method merge_config (HashRef $new_config) {
    for my $newserver (values %$new_config) {
      if (! exists $self->config->servers->{$newserver->{name}}) {
        $self->add_irc_server($newserver->{name}, $newserver);
      }
      for my $key (keys %$newserver) {
        $self->config->servers->{$newserver->{name}}{$key} = $newserver->{$key};
      }
    }
  }
  
  method tab_order (ArrayRef $window_ids) {
    my $order = [];
    for my $count (0 .. scalar @$window_ids - 1) {
      if (my $window = $self->get_window($window_ids->[$count])) {
        next unless $window->is_channel
             and $self->config->servers->{$window->connection->session_alias};
        push @$order, $window->title;
      }
    }
    $self->config->order($order);
    $self->config->write;
  }
  
  method nick_windows (Str $nick) {
    return grep {$_->includes_nick($nick)} $self->windows;
  }

  method buffered_messages (Int $min) {
    return [ map {$_->{buffered} = 1; $_;}
             grep {$_->{msgid} > $min}
             map {@{$_->msgbuffer}} $self->windows
           ];
  }

  method connections {
    return map {$_->connection} values %{$self->ircs};
  }

  method find_or_create_window (Str $title, $connection) {
    return $self->info_window if $title eq "info";
    my $id = "win_" . crc16(lc($title . $connection->session_alias));
    if (my $window = $self->get_window($id)) {
      return $window;
    }
    my $window = App::Alice::Window->new(
      title      => $title,
      connection => $connection,
      assetdir   => $self->config->assetdir,
      tt         => $self->tt,
    );  
    $self->add_window($id, $window);
  }

  method close_window (App::Alice::Window $window) {
    return unless $window;
    $self->send([$window->close_action]);
    $self->log_debug("sending a request to close a tab: " . $window->title)
      if $self->httpd->has_clients;
    $self->remove_window($window->id);
  }

  method add_irc_server (Str $name, HashRef $config) {
    $self->ircs->{$name} = App::Alice::IRC->new(
      app    => $self,
      alias  => $name,
      config => $config
    );
  }
  
  method log_info (Str $session, Str $body, Bool :$highlight = 0) {
    say STDERR "$session: $body";
    $self->info_window->render_message($session, $body, highlight => $highlight);
  }

  method send (ArrayRef $messages, Bool $force) {
    # add any highlighted messages to the log window
    push @$messages, map {$self->log_info($_->{nick}, $_->{body}, highlight => 1)}
                    grep {$_->{highlight}} @$messages;
    
    POE::Kernel->post($self->httpd->session, "send", $messages, $force);
    
    return unless $self->notifier and ! $self->httpd->has_clients;
    for my $message (@$messages) {
      $self->notifier->display($message) if $message->{highlight};
    }
  }
  
  method render_notice  (Str $event, Str $nick, Str $body) {
    $body = decode("utf8", $body, Encode::FB_WARN);
    my $message = {
      type      => "action",
      event     => $event,
      nick      => $nick,
      body      => $body,
      msgid     => App::Alice::Window->next_msgid,
    };
    my $html = '';
    $self->tt->process("event.tt", $message, \$html);
    $message->{full_html} = $html;
    $message->{event} = "notice";
    return $message;
  }

  sub log_debug {
    my $self = shift;
    say STDERR join " ", @_ if $self->config->debug;
  }
}
