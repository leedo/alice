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

  my @sigs = map {AE::signal $_, sub {$self->init_shutdown}} qw/INT QUIT/;

  $self->cv(AE::cv);
  $self->cv->recv;
};

after init => sub {
  my $self = shift;
  print STDERR "Location: http://".$self->config->http_address.":".$self->config->http_port."/\n";
};

before init_shutdown => sub {
  my $self = shift;
  print STDERR ($self->connected_ircs ? "\nDisconnecting, please wait\n" : "\n");
};

after shutdown => sub {
  my $self = shift;
  $self->cv->send;
};

1;
