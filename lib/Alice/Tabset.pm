package Alice::Tabset;

use Any::Moose;

use List::MoreUtils qw/any/;

has name => (
  is => 'ro',
  required => 1,
);

has windows => (
  is => 'ro',
  isa => 'ArrayRef',
  default => sub {[]},
);

sub includes {
  my ($self, $window_id) = @_;
  return any {$_ eq $window_id} @{$self->windows};
}

__PACKAGE__->meta->make_immutable;
1;
