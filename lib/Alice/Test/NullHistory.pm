package Alice::Test::NullHistory;

use Any::Moose;

sub store {}
sub search {}

__PACKAGE__->meta->make_immutable;
1;
