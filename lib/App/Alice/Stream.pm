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

has [qw/delayed started closed/] => (
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

has min_bytes => (
  is => 'ro',
  default => 1024,
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
  $self->_send;
}

sub _send {
  my $self = shift;
  eval { $self->send };
  warn $@ if $@;
  $self->close if $@;
}

sub send {
  my ($self, @messages) = @_;
  die "Sending on a closed stream" if $self->closed;
  $self->enqueue(@messages) if @messages;
  return if $self->delayed or $self->queue_empty;
  if (my $delay = $self->flooded) {
    $self->delay($delay);
    return;
  }
  $self->writer->write( $self->to_string );
  $self->flush;
}

sub close {
  my $self = shift;
  $self->flush;
  try {$self->writer->close} if $self->writer;
  $self->writer(undef);
  $self->timer(undef);
  $self->closed(1);
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
      $self->_send;
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

  $output .= "\n--" . $self->seperator . "\n"
          .  " " x ($self->min_bytes - length $output);

  return $output
}

__PACKAGE__->meta->make_immutable;
1;
