package Alice::Standalone;

use Any::Moose;
use AnyEvent;
use Alice::HTTP::Server;

extends 'Alice';

has cv => (is => 'rw');

after run => sub {
  my $self = shift;

  my @sigs = map {AE::signal $_, sub {$self->init_shutdown}} qw/INT QUIT/;

  $self->cv(AE::cv);
  $self->cv->recv;
};

after init => sub {
  my $self = shift;

  my $session = do {;
    my $dir = $self->config->path."/sessions";
    mkdir $dir unless -d $dir;
    Plack::Session::Store::File->new(dir => $self->config->path."/sessions"),
  };

  $self->{httpd} = Alice::HTTP::Server->new(
    app     => $self,
    port    => $self->config->http_port,
    address => $self->config->http_address,
    session => $session,
    assets  => $self->config->assetdir,
  );

  AE::log info => "Location: http://".$self->config->http_address.":".$self->config->http_port."/";
};

before init_shutdown => sub {
  my $self = shift;
  AE::log(info => "Disconnecting, please wait") if $self->connected_ircs;
};

after shutdown => sub {
  my $self = shift;
  $self->cv->send;
};

__PACKAGE__->meta->make_immutable;
1;
