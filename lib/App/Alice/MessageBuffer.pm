package App::Alice::MessageBuffer;

use Any::Moose;

has store => (
  is => 'ro',
  lazy => 1,
  default => sub {
    my $self = shift;
    eval "require App::Alice::MessageStore::".$self->store_class;
    ("App::Alice::MessageStore::".$self->store_class)->new;
  }
);

has store_class => (
  is => 'ro',
  default => 'Memory',
);

has previous_nick => (
  is => 'rw',
  default => "",
);

sub clear {
  my $self = shift;
  $self->previous_nick("");
  $self->store->clear;
}

sub add {
  my ($self, $message) = @_;
  $message->{event} ne "say" ? $self->previous_nick("")
    : $self->previous_nick($message->{nick});
  $self->store->add($message);
}

sub with_messages {
  my $self = shift;
  $self->store->with_messages(@_);
}

__PACKAGE__->meta->make_immutable;
1;
