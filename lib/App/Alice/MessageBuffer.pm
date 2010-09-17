package App::Alice::MessageBuffer;

use Any::Moose;

has previous_nick => (
  is => 'rw',
  default => "",
);

has messages => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub {[]}
);

has buffersize => (
  is => 'ro',
  default => 100
);

sub clear {
  my ($self, $cb) = @_;
  $self->previous_nick("");
  $self->messages([]);
}

sub add {
  my ($self, $message) = @_;
  $message->{event} eq "say" ? $self->previous_nick($message->{nick})
                             : $self->previous_nick("");

  push @{$self->messages}, $message;
  if (@{$self->messages} > $self->buffersize) {
    shift @{$self->messages};
  }
}

__PACKAGE__->meta->make_immutable;
1;
