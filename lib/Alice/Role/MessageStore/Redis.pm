package Alice::Role::MessageStore::Redis;

use AnyEvent::Redis;
use Any::Moose 'Role';
use JSON::XS;

has redis => (
  is => 'rw',
  default => sub { AnyEvent::Redis->new },
);

sub get_msgid {
  my ($self, $id, $cb) = @_;
  $self->redis->incr("$id-msgid", $cb);
}

sub get_messages {
  my ($self, $id, $max, $limit, $cb) = @_;

  $limit--;

  if (defined $max and $max >= 0) {
    $self->redis->get("$id-msgid", sub {
      my $msgid = shift;
      my $start = $msgid - $max;
      my $end = $start + $limit;
      $self->redis->lrange("$id-msgs", $start, $end, sub {
        my ($msgs, $err) = @_;
        AE::log warn => $err if $err;
        $cb->([map { decode_json $_ } reverse @$msgs])
      });
    });
  }

  else {
    $self->redis->lrange("$id-msgs", 0, $limit, sub {
      my ($msgs, $err) = @_;
      AE::log warn => $err if $err;
      $cb->([map { decode_json $_ } reverse @$msgs])
    });
  }
}

sub add_message {
  my ($self, $id, $message) = @_;
  $self->redis->lpush("$id-msgs", encode_json($message), sub {});
}

1;
