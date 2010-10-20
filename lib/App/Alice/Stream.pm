package App::Alice::Stream;

use Any::Moose;

has closed => (
  is => 'rw',
  default => 0,
);

has is_xhr => (
  is => 'ro',
  default => 1,
);

__PACKAGE__->meta->make_immutable;
1;
