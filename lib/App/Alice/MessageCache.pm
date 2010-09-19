package App::Alice::MessageCache;

use strict;
use warnings;

use AnyEvent;
use Any::Moose;
use JSON;
use Cache::File;

my $cache = Cache::File->new(
  cache_root => "./cache",
  lock_level => Cache::File::LOCK_NONE(),
);

$cache->clear;

# max 100KB of message HTML
# just ignore the metadata since it
# is a pretty fixed size
my $buffersize = 1024 * 100;
my ($add_queue, $add_w);

has id => (
  is => 'ro',
  required => 1,
);

has previous_nick => (
  is => 'rw',
  default => "",
);

sub DESTROY {
  my $self = shift;
  $cache->remove($self->{id});
}

sub messages {
  my ($self, $limit) = @_;

  my $json = $cache->get($self->{id});
  my $messages = $json ? decode_json $json : [];
  my $total = scalar @$messages;

  return () unless $total;

  if ($limit) {
    $limit = 0 if $limit < 0;
    $limit = $total if $limit > $total;
  }
  else {
    $limit = $total;
  }

  return @{$messages}[$total - $limit .. $total - 1];
}

sub clear {
  my $self = shift;
  $self->previous_nick("");

  my $clear_w; $clear_w = AE::idle sub {
    $cache->remove($self->{id});
    undef $clear_w;
  };
}

sub add {
  my ($self, $message) = @_;
  $message->{event} eq "say" ? $self->previous_nick($message->{nick})
                             : $self->previous_nick("");

  my $queue = $add_queue->{$self->{id}};

  if (defined $queue) {
    push @$queue, $message;
  } else {
    $add_queue->{$self->{id}} = [$message];
  }

  if (!$add_w) {  
    $add_w = AE::idle sub {
      my ($k,$v);
      while (($k, $v) = each %$add_queue) {
        my $json = $cache->get($k);
        my $msgs = ($json ? decode_json $json : []);
        push @$msgs, @$v;

        # may be better to keep a running count of the size
        # and only remove items if (past size + new size)
        # is larger than $buffersize

        my $size = 0;
        my $idx = my $length = scalar @$msgs - 1;
        while ($idx > 0) {
          # the metadata adds about 300 bytes
          $size += length($msgs->[$idx]->{html}) + 300; 
          last if $size > $buffersize;
          $idx--;
        }

        $cache->set($k, to_json [@{$msgs}[$idx .. $length]], {shrink => 1, utf8 => 1});

        delete $add_queue->{$k};
        undef $add_w if !keys %$add_queue;
      }
    };
  }
}

__PACKAGE__->meta->make_immutable;
1;
