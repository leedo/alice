package App::Alice::History;

use Any::Moose;
use AnyEvent::DBI;
use AnyEvent::IRC::Util qw/filter_colors/;
use SQL::Abstract;

has dbi => (
  is => 'ro',
  isa => 'AnyEvent::DBI',
  lazy => 1,
  default => sub {
    my $self = shift;
    AnyEvent::DBI->new("DBI:SQLite:dbname=".$self->dbfile,"","");
  }
);

has sql => (
  is => 'ro',
  isa => 'SQL::Abstract',
  default => sub {SQL::Abstract->new(cmp => "like")},
);

has dbfile => (
  is => 'ro',
  isa => 'Str',
  #required => 1,
);

sub store {
  my ($self, %fields) = @_;
  my ($stmt, @bind) = $self->sql->insert("messages", \%fields);
  $self->dbi->exec($stmt, @bind, sub {});
}

sub range {
  my $cb = pop;
  my ($self, $user, $channel, $id, $limit) = @_;
  $limit ||=5;
  $self->dbi->exec(
    "SELECT * FROM messages WHERE id < ? AND channel=? AND user=? ORDER BY id DESC LIMIT ?",
    $id, $channel, $user, $limit, sub {
      my $before = [ reverse @{$_[1]} ];
      $self->dbi->exec(
        "SELECT * FROM messages WHERE id > ? AND channel=? AND user=? ORDER BY id ASC LIMIT ?",
        $id, $channel, $user, $limit, sub {
          my $after = $_[1];
          $cb->($before, $after);
        }
      );
    }
  );
}


sub search {
  my $cb = pop;
  my ($self, %query) = @_;
  %query = map {$_ => "%$query{$_}%"} grep {$query{$_}} qw/body channel nick user/;
  my ($stmt, @bind) = $self->sql->select("messages", '*', \%query, {-desc => 'id'});
  $self->dbi->exec($stmt, @bind, sub {
    my ($db, $rows, $rv) = @_;
    $cb->($rows);
  });
}

__PACKAGE__->meta->make_immutable;
1;
