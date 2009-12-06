package App::Alice::Stream;

use JSON;
use Time::HiRes qw/time/;
use Any::Moose;

has queue => (
  is  => 'rw',
  isa => 'ArrayRef[HashRef]',
  default => sub { [] },
);

sub clear_queue {$_[0]->queue([])}
sub enqueue {push @{shift->queue}, @_}
sub queue_empty {return @{$_[0]->queue} == 0}

has [qw/offset last_send/]=> (
  is  => 'rw',
  isa => 'Num',
  default => 0,
);

has [qw/delayed started disconnected/] => (
  is  => 'rw',
  isa => 'Bool',
  default => 0,
);

has 'seperator' => (
  is  => 'ro',
  isa => 'Str',
  default => 'xalicex',
);

has 'timer' => (
  is  => 'rw',
);

has 'request' => (
  is  => 'ro',
  isa => 'AnyEvent::HTTPD::Request',
  required => 1,
);

has callback => (
  is  => 'rw',
  isa => 'CodeRef',
  default => sub {
    sub {
      print STDERR "no data callback set up on stream yet!\n"
    }
  }
);

sub BUILD {
  my $self = shift;
  my $local_time = time;
  my $remote_time = $self->request->parm('t') || $local_time;
  $self->offset($local_time - $remote_time);
  $self->request->respond([
    200, 'ok', {'Content-Type' => 'multipart/mixed; boundary='.$self->seperator.'; charset=utf-8'},
    sub {$_[0] ? $self->callback($_[0]) : $self->disconnected(1)}
  ]);
  $self->broadcast;
}

sub broadcast {
  my $self = shift;
  return if $self->delayed or $self->queue_empty;
  if (my $delay = $self->flooded) {
    $self->delay($delay);
    return;
  }
  $self->callback->( $self->to_string );
  $self->flush;
}

sub flooded {
  my $self = shift;
  my $diff = time - $self->last_send;
  if ($diff < 0.2) {
    return 0.2 - $diff;
  }
  return 0;
}

sub delay {
  my ($self, $delay) = @_;
  $self->delayed(1);
  $self->timer(AnyEvent->timer(
    after => $delay,
    cb    => sub {
      $self->delayed(0);
      $self->timer(undef);
      $self->broadcast;
    },
  ));
}

sub flush {
  my $self = shift;
  $self->clear_queue;
  $self->last_send(time);
}

sub to_string {
  my $self = shift;
  my $output;
  if (! $self->started) {
    $output .= "--".$self->seperator."\n";
    $self->started(1);
  }
  $output .= to_json({
    queue => $self->queue,
    time  => time - $self->offset,
  }, {utf8 => 1});
  use bytes;
  $output .= " " x (1024 - bytes::length $output)
    if bytes::length $output < 1024;
  no bytes;
  $output .= "\n--" . $self->seperator . "\n";
  return $output
}

__PACKAGE__->meta->make_immutable;
1;
