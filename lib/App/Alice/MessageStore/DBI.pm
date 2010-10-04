package App::Alice::MessageStore::DBI;

use AnyEvent::DBI;
use Any::Moose;
use JSON;

our $dsn = ["dbi:SQLite:dbname=share/buffer.db", "", ""];
our $dbi = AnyEvent::DBI->new(@$dsn);

has id => (
  is => 'ro',
  required => 1,
);

has del_timer => (
  is => 'rw',
  default => 0
);

sub BUILD {
  my $self = shift;
  $self->clear;
}

sub clear {
  my $self = shift;
  $dbi->exec("DELETE FROM window_buffer WHERE window_id = ?", $self->{id}, sub {});
}

sub messages {
  my ($self, $limit, $msgid, $cb) = @_;
  $dbi->exec(
    "SELECT message FROM window_buffer WHERE window_id=? AND msgid > ? ORDER BY msgid ASC LIMIT 0, ?",
    $self->{id}, $msgid, $limit, sub { $cb->([map {decode_json $_->[0]} @{$_[1]}]) }
  );
}

sub add {
  my ($self, $message) = @_;
  $dbi->exec(
    "INSERT INTO window_buffer (window_id, msgid, message) VALUES (?, ?, ?)",
    $self->{id}, $message->{msgid}, encode_json($message), sub {}
  );

  if (!$self->del_timer) {
    my $t = AE::timer 60, 0, sub {
      $self->trim;
      $self->del_timer(undef);
    };
    $self->del_timer($t);
  }
}

sub trim {
  my $self = shift;
  $dbi->exec(
    "SELECT msgid FROM window_buffer WHERE window_id=? ORDER BY msgid ASC LIMIT 100, 1",
    $self->{id}, sub {
      my $rows = $_[1];
      if (@$rows) {
        my $minid = $rows->[0][0];
        $dbi->exec(
          "DELETE FROM window_buffer WHERE window_id=? AND msgid >= ?",
          $self->{id}, $minid, sub {}
        );
      }
    }
  );
}

1;
