package App::Alice::Stream;

use Any::Moose;

has [qw/offset last_send start_time/]=> (
  is  => 'rw',
  isa => 'Num',
  default => 0,
);

has closed => (
  is => 'rw',
  default => 0,
);

sub BUILD {
  my $self = shift;

  my $local_time = time;
  my $remote_time = $self->start_time || $local_time;
  $self->offset($local_time - $remote_time);
  $self->setup_stream;
}

sub setup_stream { }

__PACKAGE__->meta->make_immutable;
1;
