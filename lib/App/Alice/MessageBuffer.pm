package App::Alice::MessageBuffer;

use Any::Moose;

my $msgid = 1;

has previous_nick => (
  is => 'rw',
  default => "",
);

has store_class => (
  is => 'ro',
  required => 1,
  default => "Memory",
);

has id => (
  is => 'ro',
  required => 1,
);

has store => (
  is => 'ro',
  lazy => 1, 
  default => sub {
    my $self = shift;
    my $class = "App::Alice::MessageStore::".$self->store_class;
    my $id = $self->id;
    my $store = eval "use $class; $class->new(id => '$id');";
    die $@ if $@;
    return $store;
  }
);

sub next_msgid {
  my $self = shift;
  return $msgid++;
}

sub clear {
  my $self = shift;
  $self->previous_nick("");

  $self->store->clear;
}

sub add {
  my ($self, $message) = @_;
  $message->{event} eq "say" ? $self->previous_nick($message->{nick})
                             : $self->previous_nick("");

  $self->store->add($message);
}

sub messages {
  my ($self, $limit, $min, $cb) = @_;

  $min = 0 unless $min > 0;
  $min = $msgid if $min > $msgid;

  $limit = $msgid - $min if $min + $limit > $msgid;
  $limit = 0 if $limit < 0;

  return $self->store->messages($limit, $min, $cb);
}

__PACKAGE__->meta->make_immutable;
1;
