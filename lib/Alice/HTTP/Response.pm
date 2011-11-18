package Alice::HTTP::Response;
use parent 'Plack::Response';
use Encode;

sub new {
  my($class, $cb, $rc, $headers, $content) = @_;

  Carp::croak(q{$cb is required})
    unless defined $cb && ref($cb) eq 'CODE';

  my $self = bless {cb => $cb}, $class;
  $self->status($rc)       if defined $rc;
  $self->headers($headers) if defined $headers;
  $self->body($content)    if defined $content;

  $self;
}

sub send {
  my $self = shift;
  my $res = $self->SUPER::finalize;
  $res->[2] = [map encode("utf8", $_), @{$res->[2]}];
  return $self->{cb}->($res);
}

sub notfound {
  my $self = shift;
  return $self->{cb}->([404, ["Content-Type", "text/plain", "Content-Length", 9], ['not found']]);
}

sub ok {
  my $self = shift;
  return $self->{cb}->([200, ["Content-Type", "text/plain", "Content-Length", 2], ['ok']]);
}

sub writer {
  my $self = shift;
  my $response = $self->SUPER::finalize;
  return $self->{cb}->([@$response[0,1]]);
}

1;
