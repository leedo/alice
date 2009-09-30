use MooseX::Declare;

class App::Alice::Signal {
  use MooseX::POE::SweetArgs qw/event/;
  
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
  
  event sigint => sub {
    my $self = shift;
    say STDERR "Closing connections, please wait.";
    $_->call(shutdown => $app->config->quitmsg) for $self->app->connections;
    POE::Kernel->delay(force_shutdown => 5);
  };

  event force_shutdown => sub {
    exit(0);
  };
}