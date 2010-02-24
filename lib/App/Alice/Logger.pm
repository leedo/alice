package App::Alice::Logger;

use Any::Moose;

has callbacks => (
  is => 'ro',
  isa => 'HashRef',
  default => sub {
    my $hashref = {map {uc $_ => [\&print_line]} qw/debug info warn error fatal/};
  }
);

sub add_cb {
  my ($self, $level, $cb) = @_;
  return unless $self->callbacks->{$level};
  push @{$self->callbacks->{$level}}, $cb;
}

sub log {
  my ($self, $level, $message) = @_;
  $level = uc $level;
  return unless @{$self->callbacks->{$level}};
  $_->($level, $message) for @{$self->callbacks->{$level}};
}

sub print_line {
  my ($level, $message) = @_;
  my ($sec, $min, $hour, $day, $mon, $year) = localtime(time);
  $level = sprintf "%-5s", $level;
  my $datestring = sprintf "%02d:%02d:%02d %02d/%02d/%02d", $hour, $min, $sec, $mon, $day, $year % 100;
  print STDERR substr($level, 0, 1) . ", [$datestring] $level -- : $message\n";
}

1;