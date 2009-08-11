package Alice::Window;

use Moose;

has is_channel => (
  is => 'ro',
  isa => 'Bool',
  default => 1,
);

has title => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has id => (
  is => 'ro',
  isa => 'Str',
  lazy => 1,
  default => sub {
    my $self = shift;
    my $id = $self->title . $self->session;
    $id =~ s/^[#&]/chan_/;
    return $id;
  }
);

has session => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has msgbuffer => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub {[]},
);

sub add_message {
  my ($self, $message) = shift;
  push @{$self->msgbuffer}, $message;
}

after add_message => sub {
  my $self = shift;
  if (@{$self->msgbuffer} > 100) {
    shift @{$self->msgbuffer};
  }
}

has 'tt' => (
  is => 'ro',
  isa => 'Template',
  default => sub {
    Template->new(
      INCLUDE_PATH => 'data/templates',
      ENCODING     => 'UTF8'
    );
  },
);

__PACKAGE__->meta->make_immutable;
no Moose;
1;