package App::Alice::MessageStore::Redis;

use Any::Moose;
use AnyEvent::Redis;
use JSON;

my $redis = AnyEvent::Redis->new;

has id => (
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
  $redis->rpush($self->id, encode_json $message);
  $redis->llen($self->id, sub {
    $redis->lpop($self->id) if $_[0] > $self->buffersize;
  });
}

sub clear {
  my ($self, $cb) = @_;

  my $wrapped = sub {
    $cb->() if $cb;
    undef $redis->{on_error};
  };

  $redis->{on_error} = $wrapped;
  $redis->del($self->id, $wrapped);
}

sub with_messages {
  my ($self, $cb, $start, $complete_cb) = @_;

  $start ||= 0;
  my $end = $start + $self->lrange_size - 1;
  $end = $self->buffersize if $end > $self->buffersize;

  $redis->{on_error} = sub {
    $cb->() if $cb;
    $complete_cb->() if $complete_cb;
    undef $redis->{on_error};
  };

  $redis->lrange(
    $self->id, $start, $end, sub {
      undef $redis->{on_error};
      my $msgs = ref $_[0] eq 'ARRAY' ? $_[0] : [];
      $cb->(
        grep {$_}
        map  {my $msg = eval {decode_json $_ }; $@ ? undef : $msg}
        @$msgs
      );
      if ($end == $self->buffersize or @$msgs != $self->lrange_size) {
        $complete_cb->() if $complete_cb;
      } else {
        $self->with_messages($cb, $end + 1, $complete_cb);
      }
    }
  );
}

__PACKAGE__->meta->make_immutable;
1;
