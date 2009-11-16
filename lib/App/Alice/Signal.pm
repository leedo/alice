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

sub sigint  {$_[0]->shutdown};
sub sigquit {$_[0]->shutdown};

sub shutdown {
  my $self = shift;
  say STDERR "Closing connections, please wait.";
  $_->disconnect for $self->app->connections;
  AnyEvent->timer(after => 3, cb => sub {exit(0)});
}

__PACKAGE__->meta->make_immutable;
1;