package App::Alice::Test::MockIRC;

use Any::Moose;

has cbs => (is => 'rw', default => sub {{}});
has nick => (is => 'rw');

sub send_srv {
  my ($self, $command, @args) = @_;
  if (exists $self->cbs->{lc $command}) {
    if ($command eq "JOIN") {
      @args = ($self->nick, $args[0], 1);
    }
    $self->cbs->{lc $command}->($self, @args);
  }
}

sub enable_ssl {}
sub ctcp_auto_reply {}
sub connect {
  my $self = shift;
  $self->cbs->{connect}->();
  $self->cbs->{registered}->();
}
sub disconnect {
  my $self = shift;
  $self->cbs->{disconnect}->();
}
sub enable_ping {}
sub send_raw {}

sub reg_cb {
  my ($self, %callbacks) = @_;
  for (keys %callbacks) {
    $self->cbs->{$_} = $callbacks{$_}; 
  }
}

1;