package App::Alice::MessageList;

use Any::Moose;

has store => (
  is => 'ro',
  default => sub {
    my $self = shift;
    eval "require ".$self->store_class;
    $self->store_class->new;
  }
);

has store_class => (
  is => 'ro',
  default => 'App::Alice::MessageList::Memory',
);

has previous_nick => (
  is => 'rw',
  default => "",
);

sub BUILD {
  my $self = shift;
  $self->store;
}

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