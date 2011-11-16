package Alice::Standalone;

use Any::Moose;
use AnyEvent;

extends 'Alice';

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
  AE::log info => "Location: http://".$self->config->http_address.":".$self->config->http_port."/";
};

before init_shutdown => sub {
  my $self = shift;
  undef $self->{message_store};
  AE::log(info => "Disconnecting, please wait") if $self->connected_ircs;
};

after shutdown => sub {
  my $self = shift;
  $self->httpd->shutdown;
  $self->cv->send;
};

1;
