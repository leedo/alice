package Alice::Role::MessageStore;

use AnyEvent::DBI;
use List::Util qw/min/;
use Any::Moose 'Role';
use JSON;

has trim_queue => (
  is => 'rw',
  default => sub {{}},
);

has backlog_size => (
  is => 'ro',
  default => 5000,
);

has trim_timer => (
  is => 'ro',
  default => sub {
    my $self = shift;
    AE::timer 60, 60, sub{$self->_do_trim};
  }
);

has dbi => (
  is => 'ro',
  lazy => 1,
  default => sub {
    my $self = shift;
    my $buffer = $self->config->path."/buffer.db";
    if (! -e  $buffer) {
      require File::Copy;
      File::Copy::copy($self->config->assetdir."/buffer.db", $buffer);
    }
    AnyEvent::DBI->new("dbi:SQLite:dbname=$buffer", "", "");
  }
);

has msgid => (
  is => 'rw',
  default => sub{{}},
);

sub get_msgid {
  my ($self, $id, $cb) = @_;
  if (exists $self->msgid->{$id}) {
    $cb->(++$self->msgid->{$id});
  }
  else {
    $self->query_msgid($id, sub {
      my $max = shift;
      $self->msgid->{$id} = $max;
      $cb->($max);
    });
  }
}

sub query_msgid {
  my ($self, $id, $cb) = @_;
  $self->dbi->exec("SELECT MAX(msgid) FROM window_buffer WHERE window_id=?", $id, sub {
    my (undef, $row) = @_;
    my ($max) = @$row ? @{$row->[0]} : 0;
    $max ||= 0;
    $cb->($max + 1);
  });
}

sub get_messages {
  my ($self, $id, $max, $limit, $cb) = @_;

  unless (defined $max and $max >= 0) {
    $max = $self->msgid->{$id};
  }

  $self->dbi->exec(
    "SELECT message FROM window_buffer WHERE window_id=? " .
    "AND msgid <= ? ORDER BY msgid DESC LIMIT ?",
    $id, $max, $limit,
    sub { $cb->([map {decode_json $_->[0]} reverse @{$_[1]}]) }
  );
}

sub add_message {
  my ($self, $id, $message) = @_;

  $self->dbi->exec(
    "INSERT INTO window_buffer (window_id,msgid,message) VALUES (?,?,?)",
    $id, $message->{msgid}, encode_json($message), sub {});

  $self->trim_queue->{$id} = 1;
}

sub _do_trim {
  my $self = shift;

  my @trim = keys %{$self->trim_queue};
  $self->trim_queue({});

  my $idle_w; $idle_w = AE::idle sub {
    if (my $window_id = shift @trim) {
      $self->_trim_id($window_id);
    }
    else {
      undef $idle_w;
    }
  };
}

sub _trim_id {
  my ($self, $window_id) = @_;
  $self->dbi->exec(
    "SELECT msgid FROM window_buffer WHERE window_id=? ORDER BY msgid DESC LIMIT ?,1",
    $window_id, $self->backlog_size, sub {
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
