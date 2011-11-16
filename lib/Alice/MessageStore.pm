package Alice::MessageStore;

use AnyEvent::DBI;
use Any::Moose;
use JSON;

has insert => (
  is => 'rw',
  default => sub {[]},
);

has trim => (
  is => 'rw',
  default => sub {{}},
);

has [qw/insert_t trim_t/] => (is => 'rw');

has dsn => (
  is => 'ro',
  required => 1,
);

has dbi => (
  is => 'ro',
  lazy => 1,
  default => sub {
    my $self = shift;
    my $dbi = AnyEvent::DBI->new(@{$self->dsn});
    $dbi->exec("SELECT msgid FROM window_buffer ORDER BY msgid DESC LIMIT 1", sub {
      $self->msgid($_[1]->[0][0] + 1) if $_[1];
    });
    $dbi;
  }
);

has msgid => (
  is => 'rw',
  default => 0,
);

sub clear {
  my ($self, $id) = @_;
  $self->dbi->exec("DELETE FROM window_buffer WHERE window_id = ?", $id, sub {});
}

sub messages {
  my ($self, $id, $limit, $msgid, $cb) = @_;
  $self->dbi->exec(
    "SELECT message FROM window_buffer WHERE window_id=? AND msgid > ? ORDER BY msgid DESC LIMIT ?",
    $id, $msgid, $limit, sub { $cb->([map {decode_json $_->[0]} reverse @{$_[1]}]) }
  );
}

sub add {
  my ($self, $id, $message) = @_;

  # collect inserts for one second
  push @{$self->insert}, [$id, $message->{msgid}, encode_json($message)];
  $self->trim->{$id} = 1;

  if (!$self->insert_t) {
    $self->insert_t(AE::timer 1, 0, sub{$self->do_insert});
  }
}

sub do_insert {
  my $self = shift;

  my $idle_w; $idle_w = AE::idle sub {
    if (my $row = shift @{$self->insert}) {
      $self->dbi->exec("INSERT INTO window_buffer (window_id, msgid, message) VALUES (?,?,?)", @$row, sub{});
    }
    else {
      undef $idle_w;
      $self->insert_t(undef);
    }
  };
  
  if (!$self->trim_t) {
    $self->trim_t(AE::timer 60, 0, sub{$self->do_trim});
  }
}

sub do_trim {
  my $self = shift;

  my @trim = keys %{$self->trim};
  $self->trim({});

  my $idle_w; $idle_w = AE::idle sub {
    if (my $window_id = shift @trim) {
      $self->trim_id($window_id);
    }
    else {
      undef $idle_w;
      $self->trim_t(undef);
    }
  };
}

sub trim_id {
  my ($self, $window_id) = @_;
  $self->dbi->exec(
    "SELECT msgid FROM window_buffer WHERE window_id=? ORDER BY msgid DESC LIMIT 100,1",
    $window_id, sub {
      my $rows = $_[1];
      if (@$rows) {
        my $minid = $rows->[0][0];
        $self->dbi->exec(
          "DELETE FROM window_buffer WHERE window_id=? AND msgid < ?",
          $window_id, $minid, sub{}
        );
      }
    }
  );
}

1;
