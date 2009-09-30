use MooseX::Declare;

class App::Alice::Config {
  use FindBin;
  use YAML qw/LoadFile DumpFile/;
  use File::ShareDir qw/dist_dir/;
  
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

  has style => (
    is      => 'rw',
    isa     => 'Str',
    default => 'default',
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

  has path => (
    is      => 'ro',
    isa     => 'Str',
    default => "$ENV{HOME}/.alice",
  );

  has file => (
    is      => 'ro',
    isa     => 'Str',
    default => "config.yaml",
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

  method load {
    my $config = {};
    mkdir $self->path if !-d $self->path;

    if (-e $self->fullpath) {
      $config = LoadFile($self->fullpath);
    }
    elsif (-e $ENV{HOME}.'/.alice.yaml') {
      say STDERR "Found config in old location, moving it to ".$self->fullpath;
      $config = LoadFile($ENV{HOME}.'/.alice.yaml');
      unlink $ENV{HOME}.'/.alice.yaml';
      DumpFile($self->fullpath, $config)
        or die "Can not write config file: $!\n";
    }
    else {
      say STDERR "No config found, writing a few config to ".$self->fullpath;
      DumpFile($self->fullpath, $config)
        or die "Can not write config file: $!\n";
    }
    $self->merge($config);
  }

  method merge (HashRef $config) {
    for my $key (keys %$config) {
      if (exists $config->{$key} and $self->meta->has_attribute($key)) {
        $self->$key($config->{$key});
      }
      else {
        say STDERR "$key is not a valid config option";
      }
    }
  }

  method write {
    mkdir $self->path if !-d $self->path;
    DumpFile($self->fullpath, $self->serialized)
      or die "Can not write config file: $!\n";
  }

  method serialized {
    { map {$_ => $self->$_} $self->meta->get_attribute_list };
  }
}
