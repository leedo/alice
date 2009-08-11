package Alice;

use Moose;
use Alice::Window;
use Alice::HTTPD;
use Alice::IRC;
use POE;

has config => (
  is => 'ro',
  isa => 'HashRef',
  required => 1,
);

has ircs => (
  is => 'ro',
  isa => 'HashRef[HashRef]',
  default => sub {{}},
);

has httpd => (
  is => 'ro',
  isa => 'Alice::HTTPD',
  lazy => 1,
  default => sub {
    Alice::HTTPD->new(app => shift);
  },
);

has dispatcher => (
  is => 'ro',
  isa => 'Alice::CommandDispatch',
  default => sub {
    Alice::CommandDispatch->new(app => shift);
  }
);

sub dispatch {
  my $self = shift;
  $self->dispatcher->handle(@_);
}

has window_map => (
  is => 'rw',
  isa => 'HashRef[Alice::Window]',
  default => sub {{}},
);

sub windows {
  my $self = shift;
  return values %{$self->window_map};
}

sub connections {
  my $self = shift;
  return map {$_->connection} values %{$self->ircs};
}

sub window {
  my ($self, $session, $title) = @_;
  my $id = $title . $session;
  $id =~ s/^[#&]/chan_/;
  return $self->window_map->{$id};
}

sub add_window {
  my ($self, $window) = @_;
  $self->window_map->{$window->id} = $window;
}

sub create_window {
  my ($self, $title, $connection) = @_;
  my $window = Alice::Window->new(
    title      => $title,
    connection => $connection,
  );
  $self->add_window($window);
  $self->send($window->join_action);
  $self->log_debug("sending a request for a new tab: " . $window->title) if $self->httpd->has_clients;
}

sub close_window {
  my ($self, $window) = @_;
  return unless $window;
  $self->send($window->close_action);
  $self->log_debug("sending a request to close a tab: " . $window->title) if $self->httpd->has_clients;
  delete $self->window_map->{$window->id};
}

sub add_irc_server {
  my ($self, $name, $config) = @_;
  $self->ircs->{$name} = Alice::IRC->new(app => $self, name => $name, config => $config);
}

sub run {
  my $self = shift;
  $self->httpd;
  $self->add_irc_server($_, $self->config->{servers}{$_})
    for keys %{$self->config->{servers}};
  POE::Kernel->run;
}

sub send {
  my $self = shift;
  $self->httpd->send_data(@_);
}

sub log_debug {
  my $self = shift;
  print STDERR join(" ", @_) . "\n";
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
