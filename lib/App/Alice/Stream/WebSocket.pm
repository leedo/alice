package App::Alice::Stream::WebSocket;

use JSON;
use Any::Moose;
use Digest::MD5 qw/md5/;
use Time::HiRes qw/time/;

extends 'App::Alice::Stream';

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

sub BUILD {
  my $self = shift;

  my $h = AnyEvent::Handle->new(fh => $self->fh);
  
  $h->on_error(sub {
    warn $_[2];
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
      sub { $self->on_read->(decode_json $_[1]) }
    );
  });
    
  $self->handle($h);
}

sub send {
  my ($self, $messages) = @_;

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
