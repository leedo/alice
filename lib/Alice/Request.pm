package Alice::Request;

use Any::Moose;

has line => (
  is => 'ro',
  required => 1,
);

has stream => (
  is => 'ro',
  required => 1,
);

has irc => (is => 'rw');

has window => (
  is => 'ro',
  required => 1,
);

sub reply {
  my ($self, $line) = @_;
  $self->stream->send({
    type => "action",
    event => "announce",
    body => $line,
  });
}

sub send_srv {
  my $self = shift;
  $self->irc->send_srv(@_) if $self->irc->is_connected;
}

sub nick {
  my $self = shift;
  $self->irc->nick;
}

__PACKAGE__->meta->make_immutable;
1;
