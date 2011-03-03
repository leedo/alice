package App::Alice;

use AnyEvent;
use Text::MicroTemplate::File;
use App::Alice::Window;
use App::Alice::InfoWindow;
use App::Alice::HTTPD;
use App::Alice::IRC;
use App::Alice::Config;
use App::Alice::Logger;
use App::Alice::History;
use App::Alice::Tabset;
use App::Alice::MessageBuffer;
use Any::Moose;
use File::Copy;
use Digest::MD5 qw/md5_hex/;
use List::Util qw/first/;
use List::MoreUtils qw/any none/;
use AnyEvent::IRC::Util qw/filter_colors/;
use IRC::Formatting::HTML qw/html_to_irc/;
use Try::Tiny;
use JSON;
use Encode;

our $VERSION = '0.19';

has config => (
  is       => 'rw',
  isa      => 'App::Alice::Config',
);

has _ircs => (
  is      => 'rw',
  isa     => 'ArrayRef',
  default => sub {[]},
);

sub ircs {@{$_[0]->_ircs}}
sub add_irc {push @{$_[0]->_ircs}, $_[1]}
sub has_irc {$_[0]->get_irc($_[1])}
sub get_irc {first {$_->alias eq $_[1]} $_[0]->ircs}
sub remove_irc {$_[0]->_ircs([ grep { $_->alias ne $_[1] } $_[0]->ircs])}
sub irc_aliases {map {$_->alias} $_[0]->ircs}
sub connected_ircs {grep {$_->is_connected} $_[0]->ircs}

has httpd => (
  is      => 'rw',
  isa     => 'App::Alice::HTTPD',
  lazy    => 1,
  default => sub {
    App::Alice::HTTPD->new(app => shift);
  },
);

has streams => (
  is      => 'rw',
  isa     => 'ArrayRef',
  default => sub {[]},
);

sub add_stream {unshift @{shift->streams}, @_}
sub no_streams {@{$_[0]->streams} == 0}
sub stream_count {scalar @{$_[0]->streams}}

has commands => (
  is      => 'ro',
  isa     => 'App::Alice::Commands',
  lazy    => 1,
  default => sub {
    App::Alice::Commands->new(commands_file => $_[0]->config->assetdir."/commands.pl");
  }
);

has history => (
  is      => 'rw',
  lazy    => 1,
  default => sub {
    my $self = shift;
    my $config = $self->config->path."/log.db";
    copy($self->config->assetdir."/log.db", $config) unless -e $config;
    App::Alice::History->new(dbfile => $config);
  },
);

sub store {
  my ($self, @args) = @_;
  return unless $self->config->logging;
  my $idle_w; $idle_w = AE::idle sub {
    $self->history->store(
      @args,
      user => $self->user,
      time => time,
    );
    undef $idle_w;
  };
}

has logger => (
  is        => 'ro',
  default   => sub {App::Alice::Logger->new},
);

sub log {$_[0]->logger->log($_[1] => $_[2]) if $_[0]->config->show_debug}

has _windows => (
  is        => 'rw',
  isa       => 'ArrayRef',
  default   => sub {[]},
);

sub windows {@{$_[0]->_windows}}
sub add_window {push @{$_[0]->_windows}, $_[1]}
sub has_window {$_[0]->get_window($_[1])}
sub get_window {first {$_->id eq $_[1]} $_[0]->windows}
sub remove_window {$_[0]->_windows([grep {$_->id ne $_[1]} $_[0]->windows])}
sub window_ids {map {$_->id} $_[0]->windows}

has 'template' => (
  is => 'ro',
  isa => 'Text::MicroTemplate::File',
  lazy => 1,
  default => sub {
    my $self = shift;
    Text::MicroTemplate::File->new(
      include_path => $self->config->assetdir . '/templates',
      cache        => 2,
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
      id       => $self->_build_window_id("info", "info"),
      assetdir => $self->config->assetdir,
      app      => $self,
    );
    $self->add_window($info);
    return $info;
  }
);

has 'user' => (
  is => 'ro',
  default => $ENV{USER}
);

sub BUILDARGS {
  my ($class, %options) = @_;

  my $self = {};

  for (qw/logger commands history template user httpd/) {
    if (exists $options{$_}) {
      $self->{$_} = $options{$_};
      delete $options{$_};
    }
  }

  $self->{config} = App::Alice::Config->new(
    %options,
    callback => sub {$self->{config}->merge(\%options)}
  );

  return $self;
}

sub run {
  my $self = shift;

  # wait for config to finish loading
  my $w; $w = AE::idle sub {
    return unless $self->config->{loaded};
    undef $w;
    $self->init;
  };
}

sub init {
  my $self = shift;
  $self->commands;
  $self->history if $self->config->logging;
  $self->info_window;
  $self->template;
  $self->httpd;

  $self->add_irc_server($_, $self->config->servers->{$_})
    for keys %{$self->config->servers};
}

sub init_shutdown {
  my ($self, $cb, $msg) = @_;

  $self->history(undef);
  $self->alert("Alice server is shutting down");
  $_->disconnect($msg) for $self->connected_ircs;

  my ($w, $t);
  my $shutdown = sub {
    $self->shutdown;
    $cb->() if $cb;
    undef $w;
    undef $t;
  };

  $w = AE::idle sub {$shutdown->() unless $self->connected_ircs};
  $t = AE::timer 3, 0, $shutdown;
}

sub shutdown {
  my $self = shift;

  $self->_ircs([]);
  $_->close for @{$self->streams};
  $self->streams([]);
}

sub reload_commands {
  my $self = shift;
  $self->commands->reload_handlers;
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
  my $window = App::Alice::Window->new(
    title    => $title,
    irc      => $connection,
    assetdir => $self->config->assetdir,
    app      => $self,
    id       => $self->_build_window_id($title, $connection->alias), 
  );
  $self->add_window($window);
  return $window;
}

sub _build_window_id {
  my ($self, $title, $session) = @_;
  md5_hex(encode_utf8(lc $self->user."-$title-$session"));
}

sub find_or_create_window {
  my ($self, $title, $connection) = @_;
  return $self->info_window if $title eq "info";

  if (my $window = $self->find_window($title, $connection)) {
    return $window;
  }

  $self->create_window($title, $connection);
}

sub sorted_windows {
  my $self = shift;
  my %o;
  if ($self->config->order) {
    %o = map {$self->config->order->[$_] => sprintf "%02d", $_ + 2}
             0 .. @{$self->config->order} - 1;
  }
  $o{info} = "01";
  sort { ($o{$a->title} || $a->sort_name) cmp ($o{$b->title} || $b->sort_name) }
       $self->windows;
}

sub close_window {
  my ($self, $window) = @_;
  $self->broadcast($window->close_action);
  $self->log(debug => "sending a request to close a tab: " . $window->title)
    if $self->stream_count;
  $self->remove_window($window->id) if $window->type ne "info";
}

sub add_irc_server {
  my ($self, $name, $config) = @_;
  $self->config->servers->{$name} = $config;
  my $irc = App::Alice::IRC->new(
    app    => $self,
    alias  => $name
  );
  $self->add_irc($irc);
}

sub reload_config {
  my ($self, $new_config) = @_;

  my %prev = map {$_ => $self->config->servers->{$_}{ircname} || ""}
             keys %{ $self->config->servers };

  if ($new_config) {
    $self->config->merge($new_config);
    $self->config->write;
  }
  
  for my $network (keys %{$self->config->servers}) {
    my $config = $self->config->servers->{$network};
    if (!$self->has_irc($network)) {
      $self->add_irc_server($network, $config);
    }
    else {
      my $irc = $self->get_irc($network);
      $config->{ircname} ||= "";
      if ($config->{ircname} ne $prev{$network}) {
        $irc->update_realname($config->{ircname});
      }
      $irc->config($config);
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
  return if $self->no_streams or !@messages;
  for my $stream (@{$self->streams}) {
    $stream->send(\@messages);
  }
}

sub ping {
  my $self = shift;
  return if $self->no_streams;
  $_->ping for grep {$_->is_xhr} @{$self->streams};
}

sub update_stream {
  my ($self, $stream, $req) = @_;

  my $min = $req->param('msgid') || 0;
  my $limit = $req->param('limit') || 100;

  $self->log(debug => "sending stream update");

  my @windows = $self->windows;

  if (my $id = $req->param('tab')) {
    if (my $active = $self->get_window($id)) {
      @windows = grep {$_->id ne $id} @windows;
      unshift @windows, $active;
    }
  }

  for my $window (@windows) {
    $self->log(debug => "updating stream from $min for ".$window->title);
    $window->buffer->messages($limit, $min, sub {
      my $msgs = shift;
      return unless @$msgs;
      $stream->send([{
        window => $window->serialized,
        type   => "chunk",
        nicks  => $window->all_nicks,
        html   => join "", map {$_->{html}} @$msgs,
      }]); 
    });
  }
}

sub handle_message {
  my ($self, $message) = @_;

  if (my $window = $self->get_window($message->{source})) {
    $message->{msg} = html_to_irc($message->{msg}) if $message->{html};

    for (split /\n/, $message->{msg}) {
      eval {
        $self->commands->handle($self, $_, $window) if length $_;
      };
      if ($@) {
        warn $@;
      }
    }
  }
}

sub send_highlight {
  my ($self, $nick, $body, $source) = @_;
  my $message = $self->info_window->format_message($nick, $body, self => 1, source => $source);
  $self->broadcast($message);
}

sub purge_disconnects {
  my ($self) = @_;
  $self->log(debug => "removing broken streams");
  $self->streams([grep {!$_->closed} @{$self->streams}]);
}

sub render {
  my ($self, $template, @data) = @_;
  $self->template->render_file("$template.html", $self, @data)->as_string;
}

sub is_highlight {
  my ($self, $own_nick, $body) = @_;
  $body = filter_colors $body;
  any {$body =~ /(?:\W|^)\Q$_\E(?:\W|$)/i }
      (@{$self->config->highlights}, $own_nick);
}

sub is_monospace_nick {
  my ($self, $nick) = @_;
  any {$_ eq $nick} @{$self->config->monospace_nicks};
}

sub is_ignore {
  my ($self, $nick) = @_;
  any {$_ eq $nick} $self->config->ignores;
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

sub static_url {
  my ($self, $file) = @_;
  return $self->config->static_prefix . $file;
}

sub auth_enabled {
  my $self = shift;

  # cache it
  if (!defined $self->{_auth_enabled}) {
    $self->{_auth_enabled} = ($self->config->auth
              and ref $self->config->auth eq 'HASH'
              and $self->config->auth->{user}
              and $self->config->auth->{pass});
  }

  return $self->{_auth_enabled};
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

sub set_away {
  my ($self, $message) = @_;
  my @args = (defined $message ? (AWAY => $message) : "AWAY");
  $_->send_srv(@args) for $self->connected_ircs;
}

sub tabsets {
  my $self = shift;
  map {
    App::Alice::Tabset->new(
      name => $_,
      windows => $self->config->tabsets->{$_},
    );
  } sort keys %{$self->config->tabsets};
}

__PACKAGE__->meta->make_immutable;
1;

=pod

=head1 NAME

App::Alice - an Altogether Lovely Internet Chatting Experience

=head1 SYNPOSIS

    my $app = App::Alice->new;
    $app->run;

=head1 DESCRIPTION

This is an overview of the App::Alice class. If you are curious
about running and/or using alice please read the L<App::Alice::Readme>.

=head2 CONSTRUCTOR

=over 4

=item App::Alice->new(%options)

App::Alice's contructor takes these options:

=item user => $username

This can be a unique name for this App::Alice instance, if none is
provided it will simply use $ENV{USER}.

=back

=head2 METHODS

=over 4

=item run

This will start the App::Alice. It will start up the HTTP server and
begin connecting to IRC servers that are set to autoconnect.

=item handle_command ($command_string, $window)

Take a string and matches it to the correct action as defined by
L<App::Alice::Command>. A source L<App::Alice::Window> must also
be provided.

=item find_window ($title, $connection)

Takes a window title and App::Alice::IRC object. It will attempt
to find a matching window and return undef if none is found.

=item alert ($alertstring)

Send a message to all connected clients. It will show up as a red
line in their currently focused window.

=item create_window ($title, $connection)

This will create a new L<App::Alice::Window> object associated
with the provided L<App::Alice::IRC> object.

=item find_or_create_window ($title, $connection)

This will attempt to find an existing window with the provided
title and connection. If no window is found it will create
a new one.

=item windows

Returns a list of all the L<App::Alice::Window>s.

=item sorted_windows

Returns a list of L<App::Alice::Windows> sorted in the order
defined by the user's config.

=item close_window ($window)

Takes an L<App::Alice::Window> object to be closed. It will
part if it is a channel and send the required messages to the
client to close the tab.

=item ircs

Returns a list of all the L<App::Alice::IRC>s.

=item connected_ircs

Returns a list of all the connected L<App::Alice::IRC>s.

=item config

Returns this instance's L<App::Alice::Config> object.

=back

=cut

