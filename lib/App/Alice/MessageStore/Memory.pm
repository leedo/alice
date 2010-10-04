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
  my ($self, $limit, $min, $cb) = @_;

  my @messages = grep {$_->{msgid} > $min} @{$self->_messages};
  my $total = scalar @messages;

  if (!$total) {
    $cb->([]);
    return;
  }
  
  $limit = $total if $limit > $total;
  $cb->([ @messages[$total - $limit .. $total - 1] ]);
}

__PACKAGE__->meta->make_immutable;
1;
