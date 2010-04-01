package App::Alice::MessageStore::Memory;

use Any::Moose;
use AnyEvent::Redis;
use Storable;

has redis => (
  is => 'rw',
  isa => 'AnyEvent::Redis',
  required => 1,
);

has queueid => (
  is => 'ro',
  required => 1
);

has buffersize => (
  is => 'ro',
  default => 100
);

has lrange_size => (
  is => 'ro',
  default => 15
);

sub add {
  my ($self, $message) = @_;
  return unless $message;
  $self->redis->rpush($self->queueid, freeze $message);
  $self->redis->llen($self->queueid, sub {
    $self->redis->lpop($self->queueid) if $_[0] > $self->buffersize;
  });
}


sub clear {
  my $self = shift;
  $self->redis->del($self->queueid);
}

sub with_messages {
  my ($self, $cb, $start, $complete_cb) = @_;

  $start ||= 0;
  my $end = $start + $self->lrange_size - 1;
  $end = $self->buffersize if $end > $self->buffersize;

  $self->app->redis->lrange(
    $self->queueid, $start, $end, sub {
      my $msgs = ref $_[0] eq 'ARRAY' ? $_[0] : [];
      $cb->(
        grep {$_}
        map  {my $msg = eval {thaw $_ }; $@ ? undef : $msg}
        @$msgs
      );
      if ($end == $self->buffersize or @$msgs != $self->lrange_size) {
        $complete_cb->() if $complete_cb;
      } else {
        $self->with_buffer($cb, $end + 1, $complete_cb);
      }
    }
  );
}


__PACKAGE__->meta->make_immutable;
1;