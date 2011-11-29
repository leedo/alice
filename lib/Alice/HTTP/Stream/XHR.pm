package Alice::HTTP::Stream::XHR;

use JSON;
use Time::HiRes qw/time/;
use Any::Moose;

extends 'Alice::HTTP::Stream';

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

has [qw/offset last_send start_time/]=> (
  is  => 'rw',
  isa => 'Num',
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

sub BUILD {
  my $self = shift;

  my $local_time = time;
  my $remote_time = $self->start_time || $local_time;
  $self->offset($local_time - $remote_time);

  # better way to get the AE handle?
  my $hdl = $self->writer->{handle};

  $hdl->{rbuf_max} = 1024 * 10;

  my $close = sub {
    $self->close;
    undef $hdl;
    $self->on_error->();
  };

  $hdl->on_eof($close);
  $hdl->on_error($close);

  $self->send([{type => "identify", id => $self->id}]);
}

sub send {
  my ($self, $messages) = @_;
  return if $self->closed;

  $messages = [$messages] if $messages and ref $messages ne "ARRAY";

  $self->enqueue(@$messages) if $messages and @$messages;
  return if $self->delayed or $self->queue_empty;

  if (my $delay = $self->flooded) {
    $self->delay($delay);
    return;
  }
  $self->send_raw( $self->to_string );
  $self->last_send(time);
  $self->flush;
}

sub send_raw {
  my ($self, $string) = @_;

  my $output;

  if (! $self->started) {
    $output .= "--$separator\n";
    $self->started(1);
  }
  
  $output .= $string;

  $output .= "\n--$separator\n"
          .  " " x ($self->min_bytes - length $output);


  $self->writer->write( $output );
}

sub ping {
  my $self = shift;
  return if $self->closed;
  $self->send([{type => "action", event => "ping"}]);
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

  return to_json({
    queue => $self->queue,
    time  => time - $self->offset,
  }, {utf8 => 1, shrink => 1});
}

__PACKAGE__->meta->make_immutable;
1;
