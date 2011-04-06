package Alice::MessageStore::TokyoCabinet;

use JSON;
use Any::Moose;
use TokyoCabinet;

my $hdb = TokyoCabinet::HDB->new;
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

# open the database
if(!$hdb->open("/tmp/alice-messages.tch", $hdb->OWRITER | $hdb->OCREAT)){
  my $ecode = $hdb->ecode;
  die ("open error: %s\n", $hdb->errmsg($ecode));
}

sub DESTROY {
  my $self = shift;
  $hdb->out($self->{id});
}

sub clear {
  my $self = shift;
  my $clear_w; $clear_w = AE::idle sub {
    $hdb->out($self->{id});
    undef $clear_w;
  };
}

sub messages {
  my ($self, $limit, $min, $cb) = @_;

  my $json = $hdb->get($self->{id});

  my $messages = $json ? decode_json $json : [];
  $messages = [ grep {$_->{msgid} > $min} @$messages ];

  my $total = scalar @$messages;

  if (!$total) {
    $cb->([]);
    return;
  }

  $limit = $total if $limit > $total;
  
  $cb->(
    [ @{$messages}[$total - $limit .. $total - 1] ]
  );
}

sub add {
  my ($self, $message) = @_;

  push @{$self->add_queue}, $message;

  if (!$self->add_watcher) {  
    my $add_w; $add_w = AE::idle sub {
      my $json = $hdb->get($self->id);
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
      
      $hdb->putasync($self->id, to_json [@{$msgs}[$idx .. $length]], {shrink => 1, utf8 => 1});

      undef $add_w;
      $self->add_queue([]);
      $self->add_watcher(undef);
    };
    $self->add_watcher($add_w);
  }
}

__PACKAGE__->meta->make_immutable;
1;
