package HTTPProxyHandler;
use base qw(Tatsumaki::Handler);
__PACKAGE__->asynchronous(1);
 
use AnyEvent::HTTP;
use Tatsumaki::HTTPClient;

sub get {
    my $self = shift;
    my $url = "http://localhost:8081" . $self->request->request_uri;
    
    # do progressive update for stream
    if ($self->request->request_uri =~ /^\/stream/) {
      http_request(GET => $url,
        on_body => sub {
          my ($body, $headers) = @_;
          $self->write($body);
          $self->flush(0);
          if (!$body) {
            $self->finish;
            return 0;
          }
          return 1;
        },
        sub {
          $self->finish;
        }
    );        
    return;
  }

  # use our own image proxy
  elsif ($self->request->request_uri =~ /^\/get\/(.+)/) {
    $url = $1;
  }

  # proxy regular requests
  Tatsumaki::HTTPClient->new->get($url, $self->async_cb(sub {
    my $res = shift;
    $self->write($res->content);
    $self->finish;
  }));
}
 
package main;
use Tatsumaki::Application;
my $app = Tatsumaki::Application->new(
  [ '/' => 'HTTPProxyHandler' ]
);
