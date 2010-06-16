package App::Alice::Commands;

use Any::Moose;
use Encode;

has 'handlers' => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub {[]},
);

has 'app' => (
  is       => 'ro',
  isa      => 'App::Alice',
  weak_ref => 1,
  required => 1,
);

sub BUILD {
  my $self = shift;
  $self->reload_handlers;
}

sub reload_handlers {
  my $self = shift;
  my $commands_file = $self->app->config->assetdir . "/commands.pl";
  if (-e $commands_file) {
    my $commands = do $commands_file;
    if ($commands and ref $commands eq "ARRAY") {
      $self->handlers($commands) if $commands;
    }
    else {
      warn "$!\n";
    }
  }
}

sub handle {
  my ($self, $command, $window) = @_;
  for my $handler (@{$self->handlers}) {
    my $re = $handler->{re};
    if ($command =~ /$re/) {
      my @args = grep {defined $_} ($5, $4, $3, $2, $1); # up to 5 captures
      if ($handler->{in_channel} and !$window->is_channel) {
        $self->reply($window, "$command can only be used in a channel");
      }
      else {
        $handler->{code}->($self, $window, @args);
      }
      return;
    }
  }
}

sub show {
  my ($self, $window, $message) = @_;
  $self->broadcast($window->format_message($window->nick, $message));
}

sub reply {
  my ($self, $window, $message) = @_;
  $self->broadcast($window->format_announcement($message));
}

sub broadcast {
  my ($self, @messages) = @_;
  $self->app->broadcast(@messages);
}

__PACKAGE__->meta->make_immutable;
1;
