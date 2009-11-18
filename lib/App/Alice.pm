package App::Alice;

use Moose;
use App::Alice::Window;
use App::Alice::InfoWindow;
use App::Alice::HTTPD;
use App::Alice::IRC;
use App::Alice::Signal;
use App::Alice::Config;
use Digest::CRC qw/crc16/;
use Encode;

our $VERSION = '0.01';

has cond => (
  is       => 'rw',
  isa      => 'AnyEvent::CondVar'
);

has config => (
  is       => 'ro',
  isa      => 'App::Alice::Config',
  default  => sub {App::Alice::Config->new},
);

has ircs => (
  is      => 'ro',
  isa     => 'HashRef',
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
      if ($^O eq 'darwin') {
        require App::Alice::Notifier::Growl;
        return App::Alice::Notifier::Growl->new;
      }
      elsif ($^O eq 'linux') {
        require App::Alice::Notifier::LibNotify;
        return App::Alice::Notifier::LibNotify->new;
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
  for my $sig (qw/INT QUIT/) {
    AnyEvent->signal(
      signal => $sig,
      cb     => sub {App::Alice::Signal->new(app => $self, type => $sig)}
    );
  }
}

sub run {
  my $self = shift;
  my $c = AnyEvent->condvar;
  
  # initialize tt and httpd because they are lazy
  $self->tt;
  $self->httpd;

  $self->add_irc_server($_, $self->config->servers->{$_})
    for keys %{$self->config->servers};

  say STDERR "Location: http://localhost:". $self->config->port ."/view";
  $c->wait;
  $_->disconnect('alice') for $self->connections;
}

sub dispatch {
  my ($self, $command, $window) = @_;
  $self->dispatcher->handle($command, $window);
}

sub merge_config {
  my ($self, $new_config) = @_;
  for my $newserver (values %$new_config) {
    if (! exists $self->config->servers->{$newserver->{name}}) {
      $self->add_irc_server($newserver->{name}, $newserver);
    }
    for my $key (keys %$newserver) {
      $self->config->servers->{$newserver->{name}}{$key} = $newserver->{$key};
    }
  }
}

sub tab_order {
  my ($self, $window_ids) = @_;
  my $order = [];
  for my $count (0 .. scalar @$window_ids - 1) {
    if (my $window = $self->get_window($window_ids->[$count])) {
      next unless $window->is_channel
           and $self->config->servers->{$window->irc->alias};
      push @$order, $window->title;
    }
  }
  $self->config->order($order);
  $self->config->write;
}

sub buffered_messages {
  my ($self, $min) = @_;
  return [ map {$_->{buffered} = 1; $_;}
           grep {$_->{msgid} > $min}
           map {@{$_->msgbuffer}} $self->windows
         ];
}

sub connections {
  my $self = shift;
  return values %{$self->ircs};
}

sub find_window {
  my ($self, $title, $connection) = @_;
  return $self->info_window if $title eq "info";
  my $id = "win_" . crc16(lc($title . $connection->alias));
  if (my $window = $self->get_window($id)) {
    return $window;
  }
}

sub find_or_create_window {
  my ($self, $title, $connection) = @_;
  return $self->info_window if $title eq "info";
  if (my $window = $self->find_window($title, $connection)) {
    return $window;
  }
  my $id = "win_" . crc16(lc($title . $connection->alias));
  my $window = App::Alice::Window->new(
    title    => $title,
    irc      => $connection,
    assetdir => $self->config->assetdir,
    tt       => $self->tt,
  );  
  $self->add_window($id, $window);
}

sub close_window {
  my ($self, $window) = @_;
  $self->send([$window->close_action]);
  $self->log_debug("sending a request to close a tab: " . $window->title)
    if $self->httpd->has_clients;
  $self->remove_window($window->id);
}

sub add_irc_server {
  my ($self, $name, $config) = @_;
  $self->ircs->{$name} = App::Alice::IRC->new(
    app    => $self,
    alias  => $name,
    config => $config
  );
}

sub log_info {
  my ($self, $session, $body, $highlight) = @_;
  $highlight = 0 unless $highlight;
  $self->info_window->render_message($session, $body, highlight => $highlight);
}

sub send {
  my ($self, $messages, $force) = @_;
  # add any highlighted messages to the log window
  push @$messages, map {$self->log_info($_->{nick}, $_->{body}, highlight => 1)}
                  grep {$_->{highlight}} @$messages;
  
  $self->httpd->broadcast($messages, $force);
  
  return unless $self->notifier and ! $self->httpd->has_clients;
  for my $message (@$messages) {
    $self->notifier->display($message) if $message->{highlight};
  }
}

sub render_notice {
  my ($self, $event, $nick, $body) = @_;
  $body = decode("utf8", $body, Encode::FB_WARN);
  my $message = {
    type      => "action",
    event     => $event,
    nick      => $nick,
    body      => $body,
    msgid     => App::Alice::Window->next_msgid,
  };
  $message->{full_html} = $self->process_template('event',$message);
  $message->{event} = "notice";
  return $message;
}

sub process_template {
  my ($self, $template, $data) = @_;
  my $output = '';
  $self->tt->process("$template.tt", $data, \$output);
  return $output;
}

sub log_debug {
  my $self = shift;
  say STDERR join " ", @_ if $self->config->debug;
}

__PACKAGE__->meta->make_immutable;
1;
