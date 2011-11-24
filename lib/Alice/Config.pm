package Alice::Config;

use FindBin;
use Data::Dumper;
use File::ShareDir qw/dist_dir/;
use List::MoreUtils qw/any/;
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

has [qw/images avatars alerts audio animate/] => (
  is      => 'rw',
  isa     => 'Str',
  default => "show",
);

has first_run => (
  is      => 'rw',
  isa     => 'Bool',
  default => 1,
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

has tabsets => (
  is      => 'rw',
  isa     => 'HashRef[ArrayRef]',
  default => sub {{}},
);

has [qw/highlights order monospace_nicks/]=> (
  is      => 'rw',
  isa     => 'ArrayRef[Str]',
  default => sub {[]},
);

has ignore => (
  is      => 'rw',
  isa     => 'HashRef[ArrayRef]',
  default => sub {
    +{ msg => [], 'join' => [], part => [], nick => [] }
  }
);


has servers => (
  is      => 'rw',
  isa     => 'HashRef[HashRef]',
  default => sub {{}},
);

has path => (
  is      => 'ro',
  isa     => 'Str',
  default => sub {$ENV{ALICE_DIR} || "$ENV{HOME}/.alice"},
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

has image_prefix => (
  is      => 'rw',
  isa     => 'Str',
  default => 'https://noembed.com/i/',
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

    my $class = "Alice::MessageStore::".$self->message_store;
    eval "require $class";

    delete $self->{callback};
    $self->{loaded} = 1;
  };

  if (-e $self->fullpath) {
    my $body;
    aio_load $self->fullpath, $body, sub {
      $config = eval $body;

      # upgrade ignore to new format
      if ($config->{ignore} and ref $config->{ignore} eq "ARRAY") {
        $config->{ignore} = {msg => $config->{ignore}};
      }

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
  my ($port, $debug, $address, $log);
  GetOptions("port=i" => \$port, "debug=s" => \$debug, "log=s" => \$log, "address=s" => \$address);
  $self->commandline->{port} = $port if $port and $port =~ /\d+/;
  $self->commandline->{address} = $address if $address;

  $AnyEvent::Log::FILTER->level($debug || "info");

  if ($log) {
    $AnyEvent::Log::COLLECT->attach(AnyEvent::Log::Ctx->new(
      level => ($debug || "info"),
      log_to_file => $log
    ));
  }
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
  aio_open $self->fullpath, POSIX::O_CREAT | POSIX::O_WRONLY | POSIX::O_TRUNC, 0644, sub {
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

sub ignores {
  my ($self, $type) = @_;
  $type ||= "msg";
  @{$self->ignore->{$type} || []}
}

sub is_ignore {
  my ($self, $type, $nick) = @_;
  $type ||= "msg";
  any {$_ eq $nick} $self->ignores($type);
}

sub add_ignore {
  my ($self, $type, $nick) = @_;
  push @{$self->ignore->{$type}}, $nick;
  $self->write;
}

sub remove_ignore {
  my ($self, $type, $nick) = @_;
  $self->ignore->{$type} = [ grep {$nick ne $_} $self->ignores($type) ];
  $self->write;
}

__PACKAGE__->meta->make_immutable;
1;
