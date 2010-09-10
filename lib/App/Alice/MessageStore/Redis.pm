package App::Alice::MessageStore::Redis;

use Any::Moose;
use AnyEvent::Redis;
use JSON;

my $redis = AnyEvent::Redis->new;
my $idle_w;

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

has queue => (
  is => 'rw',
  default => sub {[]},
);

sub add {
  my ($self, $message) = @_;
  return unless $message;

  unshift @{$self->queue}, $message;

  if (!$idle_w) {
    $idle_w = AE::idle sub {
      $redis->rpush($self->id, encode_json $_) for @{$self->queue};
      $redis->ltrim($self->id, $self->buffersize);
      $self->queue([]);
      undef $idle_w;
    };
  }
}

sub clear {
  my ($self, $cb) = @_;

  my $wrapped = sub {
    $cb->();
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
    $cb->();
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
