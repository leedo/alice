package Alice::MessageStore;

use AnyEvent::DBI;
use List::Util qw/min/;
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

has backlog => (
  is => 'ro',
  default => 5000,
);

has 'trim_timer' => (
  is => 'ro',
  default => sub {
    my $self = shift;
    AE::timer 60, 60, sub{$self->do_trim};
  }
);

has dsn => (
  is => 'ro',
  required => 1,
);

has dbi => (
  is => 'ro',
  lazy => 1,
  default => sub {
    my $self = shift;
    AnyEvent::DBI->new(@{$self->dsn});
  }
);

has msgid => (
  is => 'rw',
  default => 0,
);

sub BUILD {
  my $self = shift;
  $self->dbi->exec("SELECT msgid FROM window_buffer ORDER BY msgid DESC LIMIT 1", sub {
    my (undef, $row) = @_;
    $self->msgid( @$row ? $row->[0][0] : 0);
  });
}

sub clear {
  my ($self, $id) = @_;
  $self->dbi->exec("DELETE FROM window_buffer WHERE window_id = ?", $id, sub {});
}

sub messages {
  my ($self, $id, $max, $min, $limit, $cb) = @_;

  $self->dbi->exec(
    "SELECT message FROM window_buffer WHERE window_id=? " .
    "AND msgid <= ? AND msgid >= ? ORDER BY msgid DESC LIMIT ?",
    $id, $max, $min, $limit,
    sub { $cb->([map {decode_json $_->[0]} reverse @{$_[1]}]) }
  );
}

sub add {
  my ($self, $id, $message) = @_;

  $self->dbi->exec(
    "INSERT INTO window_buffer (window_id,msgid,message) VALUES (?,?,?)",
    $id, $message->{msgid}, encode_json($message), sub {});

  $self->trim->{$id} = 1;
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
    }
  };
}

sub trim_id {
  my ($self, $window_id) = @_;
  $self->dbi->exec(
    "SELECT msgid FROM window_buffer WHERE window_id=? ORDER BY msgid DESC LIMIT ?,1",
    $window_id, $self->backlog, sub {
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

__PACKAGE__->meta->make_immutable;
1;
