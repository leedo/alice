package Alice::Request;

use parent 'Plack::Request';
use Encode;

sub new {
  my($class, $env, $cb) = @_;

  Carp::croak(q{$env is required})
    unless defined $env && ref($env) eq 'HASH';
  Carp::croak(q{$cb is required})
    unless defined $cb && ref($cb) eq 'CODE';

  bless { env => $env, cb => $cb }, $class;
}

sub new_response {
  my $self = shift;
  Alice::Response->new($self->{cb}, @_);
}

sub param {
  my $self = shift;
  if (wantarray) {
    return map {decode("utf8", $_)} $self->SUPER::param(@_);
  }
  else {
    return decode("utf8", $self->SUPER::param(@_));
  }
}

package Alice::Response;
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
