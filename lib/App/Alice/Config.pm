package App::Alice::Config;

use FindBin;
use Data::Dumper;
use File::ShareDir qw/dist_dir/;
use Getopt::Long;
use Any::Moose;
use POSIX;

use AnyEvent::AIO;
use IO::AIO;

has assetdir => (
  is      => 'ro',
  isa     => 'Str',
  default => sub {
    if (-e "$FindBin::Bin/../share/templates") {
      return "$FindBin::Bin/../share";
    }
    return dist_dir('App-Alice');
  }
);

has [qw/images avatars alerts/] => (
  is      => 'rw',
  isa     => 'Str',
  default => "show",
);

has style => (
  is      => 'rw',
  isa     => 'Str',
  default => 'default',
);

has timeformat => (
  is      => 'rw',
  isa     => 'Str',
  default => '24',
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
  isa     => 'Str',
  default => "8080",
);

has address => (
  is      => 'rw',
  isa     => 'Str',
  default => '127.0.0.1',
);

has auth => (
  is      => 'rw',
  isa     => 'HashRef[Str]',
  default => sub {{}},
);

has [qw/ignore highlights order monospace_nicks/]=> (
  is      => 'rw',
  isa     => 'ArrayRef[Str]',
  default => sub {[]},
);

has servers => (
  is      => 'rw',
  isa     => 'HashRef[HashRef]',
  default => sub {{}},
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

has commandline => (
  is      => 'ro',
  isa     => 'HashRef',
  default => sub {{}},
);

has static_prefix => (
  is      => 'rw',
  isa     => 'Str',
  default => '/static/',
);

has message_store => (
  is      => 'rw',
  isa     => 'Str',
  default => 'Memory',
);

has callback => (
  is      => 'ro',
  isa     => 'CodeRef',
);

sub ignores {@{$_[0]->ignore}}
sub add_ignore {push @{shift->ignore}, @_}

sub BUILD {
  my $self = shift;
  $self->load;
  mkdir $self->path unless -d $self->path;
}

sub load {
  my $self = shift;
  my $config = {};

  my $loaded = sub {
    $self->read_commandline_args;
    $self->merge($config);
    $self->callback->();
    delete $self->{callback};
    $self->{loaded} = 1;
  };

  if (-e $self->fullpath) {
    my $body;
    aio_load $self->fullpath, $body, sub {
      $config = eval $body;
      if ($@) {
        warn "error loading config: $@\n";
      }
      $loaded->();
    }
  }
  else {
    say STDERR "No config found, writing a few config to ".$self->fullpath;
    $self->write($loaded);
  }
}

sub read_commandline_args {
  my $self = shift;
  my ($port, $debug, $address);
  GetOptions("port=i" => \$port, "debug" => \$debug, "address=s" => \$address);
  $self->commandline->{port} = $port if $port and $port =~ /\d+/;
  $self->commandline->{debug} = 1 if $debug;
  $self->commandline->{address} = $address if $address;
}

sub http_port {
  my $self = shift;
  if ($self->commandline->{port}) {
    return $self->commandline->{port};
  }
  return $self->port;
}

sub http_address {
  my $self = shift;
  if ($self->commandline->{address}) {
    return $self->commandline->{address};
  }
  if ($self->address eq "localhost") {
    $self->address("127.0.0.1");
  }
  return $self->address;
}

sub show_debug {
  my $self = shift;
  if ($self->commandline->{debug}) {
    return 1;
  }
  return $self->debug;
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
  my $self = shift;
  my $callback = pop;
  mkdir $self->path if !-d $self->path;
  aio_open $self->fullpath, POSIX::O_WRONLY | POSIX::O_TRUNC, 0644, sub {
    my $fh = shift;
    if ($fh) {
      local $Data::Dumper::Terse = 1;
      local $Data::Dumper::Indent = 1;
      my $config = Dumper $self->serialized;
      aio_write $fh, 0, length $config, $config, 0, sub {
        $callback->() if $callback;
      };
    }
    else {
      warn "Can not write config file: $!\n";
    }
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
