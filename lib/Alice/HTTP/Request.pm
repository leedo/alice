package Alice::HTTP::Request;

use Alice::HTTP::Response;
use Encode;

use parent 'Plack::Request';

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
  Alice::HTTP::Response->new($self->{cb}, @_);
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

1;
