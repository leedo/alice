package Alice::HTTP::Stream::WebSocket;

use JSON;
use Any::Moose;
use Digest::MD5 qw/md5/;
use Time::HiRes qw/time/;

extends 'Alice::HTTP::Stream';

has fh => (
  is => 'ro',
  required => 1,
);

has handle => (
  is => 'rw',
);

has on_read => (
  is => 'ro',
  isa => 'CodeRef',
);

has is_xhr => (
  is => 'ro',
  default => 0,
);

has ws_version => (
  is => 'rw',
  required => 1,
);

sub BUILD {
  my $self = shift;

  my $h = AnyEvent::Handle->new(
    fh => $self->fh,
    rbuf_max => 1024 * 10,
  );

  $h->{ws_version} = $self->ws_version;
  
  $h->on_error(sub {
    $self->close;
    undef $h;
    $self->on_error->();
  });

  $h->on_eof(sub {
    $self->close;
    undef $h;
    $self->on_error->();
  }); 

  $h->on_read(sub {
    $_[0]->push_read(
      'AnyEvent::Handle::Message::WebSocket',
      sub { $self->on_read->(from_json $_[1]) }
    );
  });
    
  $self->handle($h);
  $self->send([{type => "identify", id => $self->id}]);
}

sub send {
  my ($self, $messages) = @_;

  $messages = [$messages] unless ref $messages eq "ARRAY";

  my $line = to_json(
    {queue => $messages},
    {utf8 => 1, shrink => 1}
  );
  
  $self->send_raw($line);
}

sub send_raw {
  my ($self, $string) = @_;
  $self->handle->push_write(
    'AnyEvent::Handle::Message::WebSocket',
    $string
  );
}

sub close {
  my $self = shift;
  $self->handle->destroy;
  $self->closed(1);
}

__PACKAGE__->meta->make_immutable;
1;
