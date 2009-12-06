package App::Alice::Signal;

use AnyEvent;
use Any::Moose;

has type => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

has app => (
  is  => 'ro',
  isa => 'App::Alice',
  required => 1,
);

sub BUILD {
  my $self = shift;
  my $method = "sig" . lc $self->type;
  $self->$method();
}

sub sigint  {$_[0]->app->cond->send};
sub sigquit {$_[0]->app->cond->send};

__PACKAGE__->meta->make_immutable;
1;
