package App::Alice::Config;

use Moose;
use FindBin;
use Data::Dumper;
use File::ShareDir qw/dist_dir/;
use Getopt::Long;

has assetdir => (
  is      => 'ro',
  isa     => 'Str',
  default => sub {
    if (-e "$FindBin::Bin/../share/templates") {
      return "$FindBin::Bin/../share";
    }
    elsif ($FindBin::Script eq "script") {
      return "$FindBin::Bin/share";
    }
    else {
      return dist_dir('App-Alice');
    }
  }
);

has images => (
  is      => 'rw',
  isa     => 'Str',
  default => "show",
);

has quitmsg => (
  is      => 'rw',
  isa     => 'Str',
  default => 'alice.',
);

has debug => (
  is      => 'rw',
  isa     => 'Bool',
  default => 0,
);

has port => (
  is      => 'rw',
  isa     => 'Int',
  default => 8080,
);

has address => (
  is      => 'rw',
  isa     => 'Str',
  default => 'localhost',
);

has auth => (
  is      => 'rw',
  isa     => 'HashRef[Str]',
  default => sub {{}},
);

has servers => (
  is      => 'rw',
  isa     => 'HashRef[HashRef]',
  default => sub {{}},
);

has order => (
  is      => 'rw',
  isa     => 'ArrayRef[Str]',
  default => sub {[]},
);

has monospace_nicks => (
  is      => 'rw',
  isa     => 'ArrayRef[Str]',
  default => sub {['Shaniqua']},
);

has path => (
  is      => 'ro',
  isa     => 'Str',
  default => "$ENV{HOME}/.alice",
);

has file => (
  is      => 'ro',
  isa     => 'Str',
  default => "config",
);

has fullpath => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub {$_[0]->path ."/". $_[0]->file},
);

sub BUILD {
  my $self = shift;
  $self->meta->error_class('Moose::Error::Croak');
  $self->load;
}

sub load {
  my $self = shift;
  my $config = {};
  mkdir $self->path if !-d $self->path;

  if (-e $self->fullpath) {
    $config = require $self->fullpath;
  }
  elsif (-e $ENV{HOME}.'/.alice.yaml') {
    say STDERR "Found config in old location, moving it to ".$self->fullpath;
    require YAML;
    YAML->import('LoadFile');
    $config = LoadFile($ENV{HOME}.'/.alice.yaml');
    unlink $ENV{HOME}.'/.alice.yaml';
    $self->write($config);
  }
  else {
    say STDERR "No config found, writing a few config to ".$self->fullpath;
    $self->write($config);
  }
  GetOptions("port=i" => \($config->{port}), "debug" => \($config->{debug}));
  $self->merge($config);
}

sub merge {
  my ($self, $config) = @_;
  for my $key (keys %$config) {
    if (exists $config->{$key} and my $attr = $self->meta->get_attribute($key)) {
      $self->$key($config->{$key}) if $attr->has_write_method;
    }
    else {
      say STDERR "$key is not a valid config option";
    }
  }
}

sub write {
  my ($self, $data) = @_;
  my $config = $data || $self->serialized;
  mkdir $self->path if !-d $self->path;
  open my $fh, ">", $self->fullpath;
  {
    local $Data::Dumper::Terse = 1;
    print $fh Dumper($config)
      or die "Can not write config file: $!\n";
  }
}

sub serialized {
  my $self = shift;
  return {
    map {
      my $name = $_->name;
      $name => $self->$name;
    } grep {$_->has_write_method}
    $self->meta->get_all_attributes
  };
}

__PACKAGE__->meta->make_immutable;
1;
