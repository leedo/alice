package App::Alice::MessageStore::Memory;

use Any::Moose;

has _messages => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub {[]}
);

has buffersize => (
  is => 'ro',
  default => 100
);

has id => (
  is => 'ro',
  required => 1,
);

sub clear {
  my $self = shift;
  $self->_messages([]);
}

sub add {
  my ($self, $message) = @_;

  push @{$self->_messages}, $message;
  if (@{$self->_messages} > $self->buffersize) {
    shift @{$self->_messages};
  }
}

sub messages {
  my ($self, $limit) = @_;

  my $total = scalar @{$self->_messages};
  return () unless $total;
  
  if ($limit) {
    $limit = 0 if $limit < 0;
    $limit = $total if $limit > $total;
  }
  else {
    $limit = $total;
  }

  return @{$self->_messages}[$total - $limit .. $total - 1];
}

__PACKAGE__->meta->make_immutable;
1;
