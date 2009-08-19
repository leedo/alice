#!/usr/bin/perl
package Perl::App::Builder;
use Any::Moose;

use Config;
use YAML;
use YAML::Dumper; # preload: WTF
use File::Path;
use Cwd;
use Config;
use CPAN;
use CPAN::HandleConfig;
use local::lib ();

with any_moose 'X::Getopt';

has 'app' => (
    is => 'rw', isa => 'Str', lazy => 1,
    default => sub {
        # foo-bar-baz.pl => Foo Bar Baz
        my $self = shift;
        my $script = $self->script;
        $script =~ s/\.plx?$//;
        return join " ", map ucfirst, split /[ _\-]/, $script;
    },
);

has 'author' => (
    is => 'rw', isa => 'Str', default => sub { $ENV{USER} },
);

has 'icon' => (
    is => 'rw', isa => 'Str', default => sub { "appIcon.icns" },
);

has 'identifier' => (
    is => 'rw', isa => 'Str', lazy => 1,
    default => sub {
        my $self = shift;
        my $app  = $self->app;
        $app =~ tr/ //d;
        return "com.example." . $self->author . ".$app";
    },
);

has 'version' => (
    is => 'rw', isa => 'Str',
);

has 'script' => (
    is => 'rw', isa => 'Str', required => 1,
);

has 'resources' => (
    is => 'rw', isa => 'ArrayRef', default => sub { [ ] },
);

has 'default_resources' => (
    is => 'rw', isa => 'ArrayRef', lazy => 1,
    default => sub {
        my $self = shift;
        [ 'lib', $self->extlib ];
    },
);

has 'deps' => (
    is => 'rw', isa => 'ArrayRef', default => sub { [] },
);

has 'extlib' => (
    is => 'rw', isa => 'Str', default => './extlib',
);

has 'background' => (
    is => 'rw', isa => 'Bool', default => 0,
);

has '_meta' => (
    is => 'rw', isa => 'HashRef', default => sub { +{} },
);

sub run {
    my $self = shift;

    $| = 1;
    $self->read_meta;
    $self->setup_deps;
    $self->setup_version;
    $self->bundle_deps;
    $self->build_app;
}

sub read_meta {
    my $self = shift;

    my $meta = eval { YAML::LoadFile("META.yml") } or do {
        warn "No META.yml: skipping automatic dependency detection.\n" .
            "Run perl Makefile.PL NO_META=0 to generate META.yml";
        return;
    };
    $self->_meta($meta);
}

sub setup_deps {
    my $self = shift;

    my @deps = @{$self->deps || []};
    if ($self->_meta->{requires}) {
        push @deps, grep $_ ne 'perl', sort keys %{$self->_meta->{requires}};
    }
    $self->deps(\@deps);
}

sub setup_version {
    my $self = shift;
    $self->version($self->_meta->{version} || "1.0") unless $self->version;
}

sub bundle_deps {
    my $self = shift;

    CPAN::HandleConfig->load;

    $ENV{PERL5LIB} = ''; # detach existent local::lib
    import local::lib '--self-contained', $self->extlib;

    # wtf: ExtUtils::MakeMaker shipped with Leopard is old
    $ENV{PERL_MM_OPT} =~ s/INSTALL_BASE=(.*)/$& INSTALLBASE=$1/;

    # no man pages TODO: do the same with Module::Build
    $ENV{PERL_MM_OPT} .= " INSTALLMAN1DIR=none INSTALLMAN3DIR=none";
    $ENV{PERL_MM_USE_DEFAULT} = 1;

    # Remove /opt from PATH: end users won't have ports
    $ENV{PATH} = join ":", grep !/^\/opt/, split /:/, $ENV{PATH};

    CPAN::Shell->rematein("notest", "install", @{$self->deps});
}

sub build_app {
    my $self = shift;

    my $app_path = $self->app . ".app";
    if (-e $app_path) {
        rmtree($app_path);
    }

    print "Building Mac application ", $self->app, ".app ...";
    system "platypus",
        "-a", $self->app, "-o", 'None', "-u", $self->author,
        "-p", $^X, "-s", '????',
        (-e $self->icon ? ("-i", $self->icon) : ()),
        "-I", $self->identifier,
        "-N", "APP_BUNDLER=Platypus-4.0",
        (map { ("-f", "$_") } @{$self->resources}, @{$self->default_resources}),
        "-c", $self->script,
        ($self->background ? "-B" : ()),
        "-V", $self->version,
        Cwd::cwd() . "/$app_path";
    print " DONE\n";
}

package main;
Perl::App::Builder->new_with_options->run;

__END__

=head1 NAME

perl-app-builder - builds .app from perl script using Platypus

=head1 SYNOPSIS

  # reads version and deps from META.yml
  perl-app-builder.pl --script your-app.pl --resources data [--resources more_dir ...]

  # explicitly set options
  perl-app-builder.pl --script your-app.pl --app "Awesome App" --version 0.91 --identifier com.example.foo

=head1 DESCRIPTION

This is a script to turn your Perl script into Mac OS X native
application using Platypus. You need to install Platypus and its
command line tools (from its preference window) to make it work.

=head1 OPTIONS

=over 4

=item script

Script path you want to turn into an app. (Required)

=item app

The application name. (Optional)

By default this script mangles your script path into an application name. For instance if your script is I<foo-bar-baz.pl>, the app name would be I<Foo Bar Baz>.

=item author

Author name. (Optional)

By default it's your UNIX login name.

=item icon

Custom icon path (Optional)

By default, if there's an icon file named I<appIcon.icns> in your current directory, it will be used. The file should be OS X icon file instead of other formats like JPEG or PNG since Platypus command line doesn't seem to support it (even though its man page claims it does!).

=item identifier

Application identifier (Optional)

By default it creates a fake identifier using its script path.

=item version

Application version (Optional)

By default it looks at I<META.yml> in the current directory to detect  the script version. Otherwise set to 1.0.

=item extlib

extra library path to include CPAN dependencies into, using local::lib (Optional)

Defaults to I<./extlib>.

=item resources

The paths to include in the application bundle (Optional)

You can specify multiple paths by repeating this option, like:

  --resources data --resources templates

I<lib> and I<extlib> (set via C<extlib> option) will always be included as resources.

See L</RESOURCES> how to reference resource files in your script.

=item deps

Perl module dependencies (Optional)

By default the script would look at I<META.yml> in your current directory to find dependencies.

=item background

Whether to make the app run in the background: will not appear in the Dock (Optional) Defaults to 0.

=back

=head1 BOOTSTRAPPING

This script uses L<local::lib> to include modules into I<extlib> (by
default), so your project is required to include L<local::lib> module
itself, and put the library path, for instance:

  # yourscript.pl
  use FindBin;
  use lib "$FindBin::Bin/lib";
  use local::lib "$FindBin::Bin/extlib";

and include C<local/lib.pm> in your I<lib> directory.

=head1 RESOURCES

When your script is launched from application, the script is located
at I</path/App Name.app/Contents/Resources> and the directories you
added with I<--resources> are available in the same directory.

Since I<$FindBin::Bin> is set to the Resources directory, it'd be
easier if you put the script in the root directory of the project and
then access those directory files using I<$FindBin::Bin/data> for
instance. This way you don't need to change anything to make your
script work within or out of Platypus app bundle.

If you have a script in I<$ROOT/scripts> directory and access the
files in I<$ROOT/data> directory for instance, you might need to do
something like:

  use FindBin;
  my $data_dir;

  if ($ENV{APP_BUNDLER}) {
      # running on Platypus
      $data_dir = "$FindBin::Bin/data";
  } else {
      # otherwise, one directory up
      $data_dir = "$FindBin::Bin/../data";
  }

=cut
