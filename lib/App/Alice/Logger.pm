package App::Alice::Logger;

use Moose;
use AnyEvent::DBI;
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
  default => sub {SQL::Abstract->new},
);

has dbfile => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

sub log_message {
  my ($self, @fields) = @_;
  my $sth = $self->dbh->exec(
    "INSERT INTO messages (time,nick,channel,body) VALUES(?,?,?,?)"
  , @fields, sub {});
}

sub search {
  my ($self, %query) = @_;
  my ($stmt, @bind) = $self->sql->select("messages", '*', \%query);
  my $sth = $self->prepare($stmt);
  return $self->dbh->selectall_arrayref($sth, {}, @bind);
}

1;
