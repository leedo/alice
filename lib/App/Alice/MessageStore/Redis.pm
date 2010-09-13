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

has prefix => (
  is => 'rw',
  default => "alice:window",
);

sub add {
  my ($self, $message) = @_;
  return unless $message;

  unshift @{$self->{queue}}, $message;

  if (!$idle_w) {
    $idle_w = AE::idle sub {
      my $id = "$self->{prefix}:$self->{id}";
      $redis->multi;
      while ( my $msg = pop @{$self->{queue}}) {
        $redis->rpush($id, encode_json $msg);
      }
      $redis->ltrim($id, 0, $self->{buffersize});
      $redis->exec;
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
  $redis->del("$self->{prefix}:$self->{id}", $wrapped);
}

sub with_messages {
  my ($self, $cb, $start, $complete_cb) = @_;

  $start ||= 0;
  my $end = $start + $self->{lrange_size} - 1;
  $end = $self->{buffersize} if $end > $self->{buffersize};

  $redis->{on_error} = sub {
    $cb->();
    $complete_cb->() if $complete_cb;
    undef $redis->{on_error};
  };

  $redis->lrange(
    "$self->{prefix}:$self->{id}", $start, $end, sub {
      undef $redis->{on_error};
      my $msgs = ref $_[0] eq 'ARRAY' ? $_[0] : [];
      $cb->(
        grep {$_}
        map  {my $msg = eval {decode_json $_ }; $@ ? undef : $msg}
        @$msgs
      );
      if ($end == $self->{buffersize} or @$msgs != $self->{lrange_size}) {
        $complete_cb->() if $complete_cb;
      } else {
        $self->with_messages($cb, $end + 1, $complete_cb);
      }
    }
  );
}

__PACKAGE__->meta->make_immutable;
1;
