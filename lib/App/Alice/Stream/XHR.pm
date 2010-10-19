package App::Alice::Stream::XHR;

use JSON;
use Time::HiRes qw/time/;
use Any::Moose;

extends 'App::Alice::Stream';

use strict;
use warnings;

my $separator = "xalicex";
our @headers = ('Content-Type' => "multipart/mixed; boundary=$separator; charset=utf-8");

has queue => (
  is  => 'rw',
  isa => 'ArrayRef[HashRef]',
  default => sub { [] },
);

sub clear_queue {$_[0]->queue([])}
sub enqueue {push @{shift->queue}, @_}
sub queue_empty {return @{$_[0]->queue} == 0}

has [qw/delayed started/] => (
  is  => 'rw',
  isa => 'Bool',
  default => 0,
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

sub setup_stream {
  my $self = shift;

  # better way to get the AE handle?
  my $hdl = $self->writer->{handle};
  my $close = sub {
    my (undef, $fatal, $msg) = @_;
    $hdl->destroy;
    undef $hdl;
    $self->close;
  };

  $hdl->on_eof($close);
  $hdl->on_error($close);
}

sub send {
  my ($self, $messages) = @_;
  return if $self->closed;

  $self->enqueue(@$messages) if $messages and @$messages;
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
  $self->writer->close if $self->writer;
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
      $self->send;
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
    $output .= "--$separator\n";
    $self->started(1);
  }

  $output .= to_json({
    queue => $self->queue,
    time  => time - $self->offset,
  }, {utf8 => 1, shrink => 1});

  $output .= "\n--$separator\n"
          .  " " x ($self->min_bytes - length $output);

  return $output
}

__PACKAGE__->meta->make_immutable;
1;
