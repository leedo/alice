package Alice::MessageBuffer;

use Any::Moose;

has previous_nick => (
  is => 'rw',
  default => "",
);

has store => (
  is => 'ro',
  required => 1,
);

has id => (
  is => 'ro',
  required => 1,
);

sub next_msgid {
  my $self = shift;
  my $msgid = $self->store->msgid + 1;
  $self->store->msgid($msgid);
  return $msgid;
}

sub clear {
  my $self = shift;
  $self->previous_nick("");
  $self->store->clear($self->id);
}

sub add {
  my ($self, $message) = @_;
  $message->{event} eq "say" ? $self->previous_nick($message->{nick})
                             : $self->previous_nick("");

  $self->store->add($self->id, $message);
}

sub messages {
  my ($self, $max, $min, $limit, $cb) = @_;

  my $msgid = $self->store->msgid;
  $max = $msgid if $max > $msgid;
  $min = 0 if $min < 0;
  $limit = 0 if $limit < 0;

  return $self->store->messages($self->id, $max, $min, $limit, $cb);
}

__PACKAGE__->meta->make_immutable;
1;
