package App::Alice::History;

use Any::Moose;
use AnyEvent::DBI;
use AnyEvent::IRC::Util qw/filter_colors/;
use SQL::Abstract;

has dbh => (
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
  required => 1,
);

sub store {
  my ($self, @fields) = @_;
  my $sth = $self->dbh->exec(
    "INSERT INTO messages (time,nick,channel,body) VALUES(?,?,?,?)"
  , time, @fields, sub {});
}

sub search {
  my $cb = pop;
  my ($self, %query) = @_;
  %query = map {$_ => "%$query{$_}%"} grep {$query{$_}} keys %query;
  my ($stmt, @bind) = $self->sql->select("messages", '*', \%query, {-desc => 'time'});
  $self->dbh->exec($stmt, @bind, sub {
    my ($db, $rows, $rv) = @_;
    $cb->($rows);
  });
}

1;
