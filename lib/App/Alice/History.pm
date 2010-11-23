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

__PACKAGE__->meta->make_immutable;
1;
