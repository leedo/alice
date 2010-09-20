package App::Alice::MessageStore::Cache;

use strict;
use warnings;

use AnyEvent;
use Any::Moose;
use JSON;
use Cache::File;

my $cache = Cache::File->new(
  cache_root => "/tmp/alice-messagecache",
  lock_level => Cache::File::LOCK_NONE(),
);

$cache->clear;

# max 100KB of message HTML
# just ignore the metadata since it
# is a pretty fixed size
my $buffersize = 1024 * 100;

has id => (
  is => 'ro',
  required => 1,
);

has add_queue => (
  is => 'rw',
  default => sub {[]}
);

has add_watcher => (
  is => 'rw',
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

  my $clear_w; $clear_w = AE::idle sub {
    $cache->remove($self->{id});
    undef $clear_w;
  };
}

sub add {
  my ($self, $message) = @_;

  push @{$self->add_queue}, $message;

  if (!$self->add_watcher) {  
    my $add_w; $add_w = AE::idle sub {
      my $json = $cache->get($self->id);
      my $msgs = ($json ? decode_json $json : []);
      push @$msgs, @{$self->add_queue};

      my $size = 0;
      my $idx = my $length = scalar @$msgs - 1;

      while ($idx > 0) {
        # the metadata adds about 300 bytes
        $size += length($msgs->[$idx]->{html}) + 300; 
        last if $size > $buffersize;
        $idx--;
      }

      $cache->set($self->id, to_json [@{$msgs}[$idx .. $length]], {shrink => 1, utf8 => 1});

      undef $add_w;
      $self->add_queue([]);
      $self->add_watcher(undef);
    };
    $self->add_watcher($add_w);
  }
}

__PACKAGE__->meta->make_immutable;
1;
