package App::Alice::MessageStore::DBI;

use App::Alice::MessageBuffer;
use AnyEvent::DBI;
use DBI;
use Any::Moose;
use JSON;

our $dsn = ["dbi:SQLite:dbname=share/buffer.db", "", ""];
our $dbi = AnyEvent::DBI->new(@$dsn);

{
  # block to get the min msgid
  my $dbh = DBI->connect(@$dsn);
  my $row = $dbh->selectrow_arrayref("SELECT msgid FROM window_buffer ORDER BY msgid DESC LIMIT 1");
  $App::Alice::MessageBuffer::MSGID = $row->[0] + 1 if $row;
}

our $INSERT = [];
our $TRIM = {};
my ($insert_t, $trim_t);

has id => (
  is => 'ro',
  required => 1,
);

sub clear {
  my $self = shift;
  $dbi->exec("DELETE FROM window_buffer WHERE window_id = ?", $self->{id}, sub {});
}

sub messages {
  my ($self, $limit, $msgid, $cb) = @_;
  $dbi->exec(
    "SELECT message FROM window_buffer WHERE window_id=? AND msgid > ? ORDER BY msgid DESC LIMIT ?",
    $self->id, $msgid, $limit, sub { $cb->([map {decode_json $_->[0]} reverse @{$_[1]}]) }
  );
}

sub add {
  my ($self, $message) = @_;

  # collect inserts for one second

  push @$INSERT, [$self->{id}, $message->{msgid}, encode_json($message)];
  $TRIM->{$self->{id}} = 1;

  if (!$insert_t) {
    $insert_t = AE::timer 1, 0, \&_handle_insert;
  }
}

sub _handle_insert {
  my $idle_w; $idle_w = AE::idle sub {
    if (my $row = shift @$INSERT) {
      $dbi->exec("INSERT INTO window_buffer (window_id, msgid, message) VALUES (?,?,?)", @$row, sub{});
    }
    else {
      undef $idle_w;
      undef $insert_t;
    }
  };
  
  if (!$trim_t) {
    $trim_t = AE::timer 60, 0, \&_handle_trim;
  }
}

sub _handle_trim {
  my @trim = keys %$TRIM;
  $TRIM = {};

  my $idle_w; $idle_w = AE::idle sub {
    if (my $window_id = shift @trim) {
      _trim($window_id);
    }
    else {
      undef $idle_w;
      undef $trim_t;
    }
  };
}

sub _trim {
  my $window_id = shift;
  $dbi->exec(
    "SELECT msgid FROM window_buffer WHERE window_id=? ORDER BY msgid DESC LIMIT 100,1",
    $window_id, sub {
      my $rows = $_[1];
      if (@$rows) {
        my $minid = $rows->[0][0];
        $dbi->exec(
          "DELETE FROM window_buffer WHERE window_id=? AND msgid < ?",
          $window_id, $minid, sub{}
        );
      }
    }
  );
}

1;
