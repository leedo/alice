package Alice::Stream;

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

1;
