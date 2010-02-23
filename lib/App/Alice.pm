package App::Alice;

use Text::MicroTemplate::File;
use App::Alice::Window;
use App::Alice::InfoWindow;
use App::Alice::HTTPD;
use App::Alice::IRC;
use App::Alice::Signal;
use App::Alice::Config;
use App::Alice::Logger;
use App::Alice::History;
use Any::Moose;
use File::Copy;

our $VERSION = '0.10';

has cond => (
  is       => 'rw',
  isa      => 'AnyEvent::CondVar'
);

has config => (
  is       => 'ro',
  isa      => 'App::Alice::Config',
);

has msgid => (
  is        => 'rw',
  isa       => 'Int',
  default   => 1,
);

sub next_msgid {$_[0]->msgid($_[0]->msgid + 1)}

has irc_map => (
  is      => 'ro',
  isa     => 'HashRef',
  default => sub {{}},
);

sub ircs {values %{$_[0]->irc_map}}
sub add_irc {$_[0]->irc_map->{$_[1]} = $_[2]}
sub has_irc {exists $_[0]->irc_map->{$_[1]}}
sub get_irc {$_[0]->irc_map->{$_[1]}}
sub remove_irc {delete $_[0]->irc_map->{$_[1]}}
sub irc_aliases {keys %{$_[0]->irc_map}}
sub connected_ircs {grep {$_->is_connected} $_[0]->ircs}

has standalone => (
  is      => 'ro',
  isa     => 'Bool',
  default => 1,
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
  lazy    => 1,
  default => sub {
    my $self = shift;
    my $notifier;
    eval {
      if ($^O eq 'darwin') {
        # 5.10 doesn't seem to put Extras in @INC
        # need this for Foundation.pm
        if ($] >= 5.01 and -e "/System/Library/Perl/Extras/5.10.0") {
          require lib;
          lib->import("/System/Library/Perl/Extras/5.10.0"); 
        }
        require App::Alice::Notifier::Growl;
        $notifier = App::Alice::Notifier::Growl->new;
      }
      elsif ($^O eq 'linux') {
        require App::Alice::Notifier::LibNotify;
        $notifier = App::Alice::Notifier::LibNotify->new;
      }
    };
    $self->log(info => "Notifications disabled") unless $notifier;
    return $notifier;
  }
);

has history => (
  is      => 'ro',
  lazy    => 1,
  default => sub {
    my $self = shift;
    if (! -e $self->config->path ."/log.db") {
      copy($self->config->assetdir."/log.db",
           $self->config->path."/log.db");
    }
    App::Alice::History->new(
      dbfile => $self->config->path ."/log.db"
    );
  },
);

sub store {
  my $self = shift;
  $self->history->store(@_);
}

has logger => (
  is        => 'ro',
  default   => sub {App::Alice::Logger->new},
);

sub log {$_[0]->logger->log($_[1] => $_[2]) if $_[0]->config->show_debug}

has window_map => (
  is        => 'rw',
  isa       => 'HashRef[App::Alice::Window|App::Alice::InfoWindow]',
  default   => sub {{}},
);

sub windows {values %{$_[0]->window_map}}
sub add_window {$_[0]->window_map->{$_[1]} = $_[2]}
sub has_window {exists $_[0]->window_map->{$_[1]}}
sub get_window {$_[0]->window_map->{$_[1]}}
sub remove_window {delete $_[0]->window_map->{$_[1]}}
sub window_ids {keys %{$_[0]->window_map}}

has 'template' => (
  is => 'ro',
  isa => 'Text::MicroTemplate::File',
  lazy => 1,
  default => sub {
    my $self = shift;
    Text::MicroTemplate::File->new(
      include_path => $self->config->assetdir . '/templates',
      cache        => 1,
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
      app      => $self,
    );
    $self->add_window($info->title, $info);
    return $info;
  }
);

has 'shutting_down' => (
  is => 'rw',
  default => 0,
  isa => 'Bool',
);

sub BUILDARGS {
  my ($class, %options) = @_;
  my $self = {standalone => 1};
  for (qw/standalone history notifier/) {
    if (exists $options{$_}) {
      $self->{$_} = $options{$_};
      delete $options{$_};
    }
  }
  $self->{config} = App::Alice::Config->new(%options);
  return $self;
}

sub run {
  my $self = shift;
  # initialize template and httpd because they are lazy
  $self->info_window;
  $self->template;
  $self->httpd;
  $self->notifier;

  print STDERR "Location: http://".$self->config->http_address.":". $self->config->http_port ."/view\n\n";

  $self->add_irc_server($_, $self->config->servers->{$_})
    for keys %{$self->config->servers};
  
  if ($self->standalone) { 
    $self->cond(AnyEvent->condvar);
    my @sigs;
    for my $sig (qw/INT QUIT/) {
      my $w = AnyEvent->signal(
        signal => $sig,
        cb     => sub {App::Alice::Signal->new(app => $self, type => $sig)}
      );
      push @sigs, $w;
    }

    $self->cond->wait;
    print STDERR "\nDisconnecting, please wait\n";
    $self->httpd->ping_timer(undef);
    $self->shutting_down(1);
    $_->disconnect('alice') for $self->connected_ircs;
    my $timer = AnyEvent->timer(
      after => 3,
      cb    => sub{$self->cond->send}
    );
    $self->cond(AE::cv)->wait;
  }
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
  return map {$_->{buffered} = 1; $_;}
         grep {$_->{msgid} > $min or $min > $self->msgid}
         map {@{$_->msgbuffer}} $self->windows;
}

sub find_window {
  my ($self, $title, $connection) = @_;
  return $self->info_window if $title eq "info";
  my $id = _build_window_id($title, $connection->alias);
  if (my $window = $self->get_window($id)) {
    return $window;
  }
}

sub create_window {
  my ($self, $title, $connection) = @_;
  my $id = _build_window_id($title, $connection->alias);
  my $window = App::Alice::Window->new(
    title    => $title,
    irc      => $connection,
    assetdir => $self->config->assetdir,
    app      => $self,
  );
  $self->add_window($id, $window);
  return $window;
}

sub _build_window_id {
  my ($title, $connection_alias) = @_;
  my $name = lc($title . $connection_alias);
  $name =~ s/[^\w\d]//g;
  return "win_" . $name;
}

sub find_or_create_window {
  my ($self, $title, $connection) = @_;
  return $self->info_window if $title eq "info";
  if (my $window = $self->find_window($title, $connection)) {
    return $window;
  }
  else {
    $self->create_window($title, $connection);
  }
}

sub sorted_windows {
  my $self = shift;
  my %order;
  if ($self->config->order) {
    %order = map {$self->config->order->[$_] => $_}
             0 .. @{$self->config->order} - 1;
  }
  $order{info} = "##";
  sort {
    my ($c, $d) = ($a->title, $b->title);
    $c =~ s/^#//;
    $d =~ s/^#//;
    $c = $order{$a->title} . $c if exists $order{$a->title};
    $d = $order{$b->title} . $d if exists $order{$b->title};
    $c cmp $d;
  } $self->windows
}

sub close_window {
  my ($self, $window) = @_;
  $self->broadcast($window->close_action);
  $self->log(debug => "sending a request to close a tab: " . $window->title)
    if $self->httpd->stream_count;
  $self->remove_window($window->id);
}

sub add_irc_server {
  my ($self, $name, $config) = @_;
  my $irc = App::Alice::IRC->new(
    app    => $self,
    alias  => $name,
    config => $config
  );
  $self->add_irc($name, $irc);
}

sub reload_config {
  my $self = shift;
  for my $irc (keys %{$self->config->servers}) {
    if (!$self->has_irc($irc)) {
      $self->add_irc_server(
        $irc, $self->config->servers->{$irc}
      );
    }
    else {
      $self->get_irc($irc)->config($self->config->servers->{$irc});
    }
  }
  for my $irc ($self->ircs) {
    if (!$self->config->servers->{$irc->alias}) {
      $self->remove_window($_->id) for $irc->windows;
      $irc->remove;
    }
  }
}

sub format_info {
  my ($self, $session, $body, $highlight, $monospaced) = @_;
  $highlight = 0 unless $highlight;
  $self->info_window->format_message($session, $body, $highlight, $monospaced);
}

sub broadcast {
  my ($self, @messages) = @_;
  # add any highlighted messages to the log window
  push @messages, map {$self->log_info($_->{nick}, $_->{body}, 1)}
                  grep {$_->{highlight}} @messages;
  
  $self->httpd->broadcast(@messages);
  
  return unless $self->notifier and ! $self->httpd->stream_count;
  for my $message (@messages) {
    $self->notifier->display($message) if $message->{highlight};
  }
}

sub format_notice {
  my ($self, $event, $nick, $body) = @_;
  my $message = {
    type      => "action",
    event     => $event,
    nick      => $nick,
    body      => $body,
    msgid     => $self->next_msgid,
  };
  $message->{full_html} = $self->render('event',$message);
  $message->{event} = "notice";
  return $message;
}

sub render {
  my ($self, $template, @data) = @_;
  return $self->template->render_file("$template.html", $self, @data)->as_string;
}

sub is_ignore {
  my ($self, $nick) = @_;
  for ($self->config->ignores) {
    return 1 if $nick eq $_;
  }
  return 0;
}

sub add_ignore {
  my ($self, $nick) = @_;
  $self->config->add_ignore($nick);
  $self->config->write;
}

sub remove_ignore {
  my ($self, $nick) = @_;
  $self->config->ignore([ grep {$nick ne $_} $self->config->ignores ]);
  $self->config->write;
}

sub ignores {
  my $self = shift;
  return $self->config->ignores;
}

__PACKAGE__->meta->make_immutable;
1;
