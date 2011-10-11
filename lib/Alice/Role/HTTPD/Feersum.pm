package Alice::Role::HTTPD::Feersum;

use Any::Moose 'Role';

use Feersum;
use Socket qw/SOMAXCONN/;
use IO::Socket::INET;
use Class::Throwable qw/SocketFailure/;

with 'Alice::Role::HTTPD';

sub build_httpd {
  my $self = shift;
  my $httpd = Feersum->endjinn;
  my $sock = IO::Socket::INET->new(
    LocalAddr => $self->config->http_address.":".$self->config->http_port,
    ReuseAddr => 1,
    Proto => 'tcp',
    Listen => SOMAXCONN,
    Blocking => 0,
  );
  throw SocketFailure "could not create socket" unless $sock;
  $httpd->use_socket($sock);

  return $httpd;
}

sub register_app {
  my ($self, $app) = @_;
  $self->httpd->psgi_request_handler($app);
}

1;
