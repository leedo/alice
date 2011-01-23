package App::Alice::Standalone;

use Any::Moose;
use AnyEvent;

extends 'App::Alice';

has cv => (
  is       => 'rw',
  isa      => 'AnyEvent::CondVar'
);

after run => sub {
  my $self = shift;

  print STDERR "Location: http://".$self->config->http_address.":".$self->config->http_port."/\n";

  $self->cv(AE::cv);

  my @sigs = map {AE::signal $_, sub {$self->cv->send}} qw/INT QUIT/;

  my $args = $self->cv->recv;
  $self->init_shutdown(@$args);
};

around init_shutdown => sub {
  my $orig = shift;
  my $self = shift;
  $self->cv(AE::cv);

  print STDERR "\nDisconnecting, please wait\n" if $self->connected_ircs;
  $self->$orig(@_);

  $self->cv->recv;
  $self->shutdown;
};

before shutdown => sub {
  my $self = shift;
  $self->cv->send;
};

1;
