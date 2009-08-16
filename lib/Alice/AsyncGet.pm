package Alice::AsyncGet;

use strict;
use warnings;
use POE qw/Wheel::Run Filter::Reference/;
use LWP::UserAgent;
use URI::http;

use Exporter;
our @ISA    = qw/Exporter/;
our @EXPORT = qw/async_fetch/;

my %children;
my @pending;

sub async_fetch {
  my ($res,$uri)  = @_;
  if (scalar keys(%children) >= 5) {
    push @pending, {
      res   => $res,
      uri   => $uri,
    };
    return 0;
  }
  
  my $pathobj  = URI->new($uri);
  my $path     = $pathobj->path();
  $path        =~ s/^\/[^\/]+\///;

  POE::Session->create(
    inline_states => {
      _start  => \&async_spawn,
      done    => \&return_object,
      debug   => sub { print STDERR "Debug: ", $_[ARG0] },
      sigchld => \&sig_child,
    },
    heap      => {
      path    => $path,
      res     => $res,
    }
  );
}

sub async_spawn {
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  my $child = POE::Wheel::Run->new(
    Program       => sub { fetch_image($heap->{path}) },
    StdoutFilter  => POE::Filter::Reference->new(),
    StdoutEvent   => 'done',
    StderrEvent   => 'debug',
  );

  # It's important to handle sigchld so POE reaps processes
  $kernel->sig_child($child->PID, 'sigchld');
  # We have to store a reference to the child or it will be
  # reaped before it runs it seems
  $children{$child->PID}  = $child;
}

sub fetch_image {
  binmode(STDOUT);    # Apparently required for Win32 :(

  my $path    = shift;
  my $filter  = POE::Filter::Reference->new();
  my $ua      = LWP::UserAgent->new(timeout => 10);

  my $res     = $ua->get($path);

  my %ret;
  if ($res->is_success) {
    %ret = (
      code    => $res->code,
      type    => $res->header('Content-Type'),
      content => $res->decoded_content,
    );
  } else {
    %ret = (
      code    => 404,
      type    => 'text/plain',
      content => "Failed to get $path\n",
    );
  }

  my $output  = $filter->put([\%ret]);
  print @$output;
}

sub return_object {
  my ($heap, $output) = @_[HEAP,ARG0];
  my $res = $heap->{res};
  
  $res->header('Content-Type' => $output->{type});
  $res->content($output->{content});
  $res->code($output->{code});
  $res->continue;
}

sub sig_child {
  my ($pid, $exit)  = @_[ARG1,ARG2];
  delete $children{$pid};
  print STDERR "PID $pid exited with status $exit\n";

  if (my $next  = shift(@pending)) {
    async_fetch($next->{res},$next->{uri});
  }
}

1;
