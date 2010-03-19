package App::Alice::Stream;

use JSON;
use Time::HiRes qw/time/;
use Try::Tiny;
use Any::Moose;

use strict;
use warnings;

has queue => (
  is  => 'rw',
  isa => 'ArrayRef[HashRef]',
  default => sub { [] },
);

sub clear_queue {$_[0]->queue([])}
sub enqueue {push @{shift->queue}, @_}
sub queue_empty {return @{$_[0]->queue} == 0}

has [qw/offset last_send start_time/]=> (
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

has 'writer' => (
  is  => 'rw',
  required => 1,
);

has callback => (
  is  => 'rw',
  isa => 'CodeRef',
  default => sub {sub{}}
);

sub BUILD {
  my $self = shift;
  my $local_time = time;
  my $remote_time = $self->start_time || $local_time;
  $self->offset($local_time - $remote_time);
  my $writer = $self->writer->(
    [200, ['Content-Type' => 'multipart/mixed; boundary='.$self->seperator.'; charset=utf-8']]
  );
  $self->writer($writer);
  $self->broadcast;
}

sub broadcast {
  my $self = shift;
  return if $self->delayed or $self->queue_empty;
  if (my $delay = $self->flooded) {
    $self->delay($delay);
    return;
  }
  try {
    $self->writer->write( $self->to_string );
  } catch {
    $self->close;
  };
  $self->flush;
}

sub close {
  my $self = shift;
  $self->writer->close;
  $self->timer(undef);
  $self->disconnected(1);
}

sub flooded {
  my $self = shift;
  my $diff = time - $self->last_send;
  if ($diff < 0.1) {
    return 0.1 - $diff;
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
