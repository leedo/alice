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
use Digest::MD5 qw/md5_hex/;
use Encode;

our $VERSION = '0.12';

has condvar => (
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
  is      => 'rw',
  isa     => 'HashRef[App::Alice::IRC]',
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
  is      => 'rw',
  isa     => 'App::Alice::HTTPD',
  lazy    => 1,
  default => sub {
    App::Alice::HTTPD->new(app => shift);
  },
);

has commands => (
  is      => 'ro',
  isa     => 'App::Alice::Commands',
  default => sub {
    App::Alice::Commands->new(app => shift);
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
  is      => 'rw',
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

has 'user' => (
  is => 'ro',
  default => $ENV{USER}
);

sub BUILDARGS {
  my ($class, %options) = @_;
  my $self = {standalone => 1};
  for (qw/standalone history notifier template/) {
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

  print STDERR "Location: http://".$self->config->http_address.":".$self->config->http_port."/\n";

  $self->add_irc_server($_, $self->config->servers->{$_})
    for keys %{$self->config->servers};
  
  if ($self->standalone) { 
    $self->condvar(AnyEvent->condvar);
    my @sigs;
    for my $sig (qw/INT QUIT/) {
      my $w = AnyEvent->signal(
        signal => $sig,
        cb     => sub {App::Alice::Signal->new(app => $self, type => $sig)}
      );
      push @sigs, $w;
    }

    $self->condvar->recv;
  }
}

sub init_shutdown {
  my ($self, $cb, $msg) = @_;
  $self->{on_shutdown} = $cb;
  $self->shutting_down(1);
  $self->alert("Alice server is shutting down");
  if ($self->ircs) {
    print STDERR "\nDisconnecting, please wait\n" if $self->standalone;
    $_->init_shutdown($msg) for $self->ircs;
  }
  else {
    $self->shutdown;
    return;
  }
  $self->{shutdown_timer} = AnyEvent->timer(
    after => 3,
    cb    => sub{$self->shutdown}
  );
}

sub shutdown {
  my $self = shift;
  $self->irc_map({});
  $self->httpd->shutdown;
  $self->history(undef);
  delete $self->{shutdown_timer} if $self->{shutdown_timer};
  $self->{on_shutdown}->() if $self->{on_shutdown};
  $self->condvar->send if $self->condvar;
}

sub handle_command {
  my ($self, $command, $window) = @_;
  $self->commands->handle($command, $window);
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

sub with_messages {
  my ($self, $cb) = @_;
  $_->buffer->with_messages($cb) for $self->windows;
}

sub find_window {
  my ($self, $title, $connection) = @_;
  return $self->info_window if $title eq "info";
  my $id = $self->_build_window_id($title, $connection->alias);
  if (my $window = $self->get_window($id)) {
    return $window;
  }
}

sub alert {
  my ($self, $message) = @_;
  return unless $message;
  $self->broadcast({
    type => "action",
    event => "alert",
    body => $message,
  });
}

sub create_window {
  my ($self, $title, $connection) = @_;
  my $id = $self->_build_window_id($title, $connection->alias);
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
  my ($self, $title, $connection_alias) = @_;
  return "win_" . md5_hex(encode_utf8(lc $self->user."-$title-$connection_alias"));
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
  $self->remove_window($window->id) if $window->type ne "info";
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
  my ($self, $session, $body, %options) = @_;
  $self->info_window->format_message($session, $body, %options);
}

sub broadcast {
  my ($self, @messages) = @_;
  
  # add any highlighted messages to the log window
  push @messages, map {$self->info_window->copy_message($_)}
                  grep {$_->{highlight}} @messages;
  
  $self->httpd->broadcast(@messages);
  
  return unless $self->notifier and ! $self->httpd->stream_count;
  for my $message (@messages) {
    next if !$message->{window} or $message->{window}{type} eq "info";
    $self->notifier->display($message) if $message->{highlight};
  }
}

sub render {
  my ($self, $template, @data) = @_;
  return $self->template->render_file("$template.html", $self, @data)->as_string;
}

sub is_monospace_nick {
  my ($self, $nick) = @_;
  for (@{$self->config->monospace_nicks}) {
    return 1 if $_ eq $nick;
  }
  return 0;
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

sub auth_enabled {
  my $self = shift;
  return ($self->config->auth
      and ref $self->config->auth eq 'HASH'
      and $self->config->auth->{user}
      and $self->config->auth->{pass});
}

sub authenticate {
  my ($self, $user, $pass) = @_;
  $user ||= "";
  $pass ||= "";
  if ($self->auth_enabled) {
    return ($self->config->auth->{user} eq $user
       and $self->config->auth->{pass} eq $pass);
  }
  return 1;
}

__PACKAGE__->meta->make_immutable;
1;
