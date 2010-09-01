package App::Alice::MessageStore::Memory;

use Any::Moose;

has msgbuffer => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub {[]}
);

has buffersize => (
  is => 'ro',
  default => 100
);

sub add {
  my ($self, $message) = @_;
  push @{$self->msgbuffer}, $message;
  if (@{$self->msgbuffer} > $self->buffersize) {
    shift @{$self->msgbuffer};
  }
}

sub clear {
  my ($self, $cb) = @_;
  $self->msgbuffer([]);
  $cb->();
}

sub with_messages {
  my ($self, $cb, $start, $complete_cb) = @_;
  $cb->(@{ $self->msgbuffer });
  $complete_cb->() if $complete_cb;
}

__PACKAGE__->meta->make_immutable;
1;
