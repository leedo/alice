package Alice::HTTP::Stream;

our $NEXT_ID = 1;

use Any::Moose;

has closed => (
  is => 'rw',
  default => 0,
);

has on_error => (
  is => 'ro',
  required => 1,
);

has is_xhr => (
  is => 'ro',
  default => 1,
);

has id => (
  is => 'rw',
  default => sub { $NEXT_ID++ }
);

sub reply {
  my ($self, $line) = @_;
  $self->send({
    type => "action",
    event => "announce",
    body => $line,
  });
}

__PACKAGE__->meta->make_immutable;

1;
