package Sprockets;

use Any::Moose;
use List::MoreUtils qw/any/;
use File::Which qw/which/;
use IPC::Open3;

has 'bin' => (
  is    => 'ro',
  isa   => 'Str',
  default => sub {
    my $path = which('sprocketize');
    die "sprocketize not available\n" if ! $path;
    return $path;
  }
);

has 'root' => (
  is    => 'rw',
  isa   => 'Str',
);

has 'load_path' => (
  is      => 'rw',
  isa     => 'ArrayRef[Str]',
  default => sub {[]},
);

sub add_load_path {push @{shift->load_path}, @_}
sub _filter_laod_path {grep $_[1] @{$_[0]->load_path}}

has 'asset_root' => (
  is  => 'rw',
  isa => 'Str',
);

sub remove_load_path {
  my ($self, @remove) = @_;
  $self->load_path([
    $self->_filter_load_path(sub {any {$_[0] ne $_} @remove})
  ]);
}

sub options {
  my $self = shift;
  my @options = map {("-I", $_)} @{$self->load_path};
  push @options, "-D", $self->root if $self->root;
  push @options, "-a", $self->asset_root if $self->asset_root;
  return @options;
}

sub concatenation {
  my ($self, @files) = @_;
  my $err = 1; # $err needs to be true for open3 to use it
  my $pid = open3(my $in, my $out, $err, $self->bin, $self->options, @files);
  waitpid $pid, 0;
  my $stdout = join "", <$out>;
  my $stderr = join "", <$err>;
  warn $stderr if $stderr;
  return $stdout;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
