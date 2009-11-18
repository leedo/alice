package App::Alice::Signal;

use AnyEvent;
use Moose;

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

sub START {
  my $self = shift;
  $self->meta->error_class('Moose::Error::Croak');
  $self->call("sig" . lc $self->type);
}

sub sigint  {$_[0]->app->cond->send};
sub sigquit {$_[0]->app->cond->send};

__PACKAGE__->meta->make_immutable;
1;