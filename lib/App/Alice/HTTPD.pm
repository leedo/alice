use MooseX::Declare;

class App::Alice::HTTPD {
  use MooseX::POE::SweetArgs qw/event/;
  use POE::Component::Server::HTTP;
  use App::Alice::AsyncGet;
  use App::Alice::CommandDispatch;
  use bytes;
  use MIME::Base64;
  use Time::HiRes qw/time/;
  use JSON;
  use Template;
  use URI::QueryParam;
  use YAML qw/DumpFile/;
  use Compress::Zlib;

  has 'app' => (
    is  => 'ro',
    isa => 'App::Alice',
    required => 1,
  );

  has 'streams' => (
    is  => 'rw',
    isa => 'ArrayRef[POE::Component::Server::HTTP::Response]',
    default => sub {[]},
  );

  has 'seperator' => (
    is  => 'ro',
    isa => 'Str',
    default => '--xalicex',
  );

  has 'commands' => (
    is => 'ro',
    isa => 'ArrayRef[Str]',
    default => sub { [qw/join part names topic me query/] },
    lazy => 1,
  );
  
  has 'assetdir' => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    default => sub { shift->app->assetdir }
  );
  
  has 'tt' => (
    is => 'ro',
    isa => 'Template',
    lazy => 1,
    default => sub { shift->app->tt }
  );

  sub BUILD {
    my $self = shift;
    POE::Component::Server::HTTP->new(
      Port            => $self->config->{port},
      Address         => $self->config->{address},
      PreHandler      => {
        '/'             => sub{$self->check_authentication(@_)},
      },
      ContentHandler  => {
        '/serverconfig' => sub{$self->server_config(@_)},
        '/config'       => sub{$self->send_config(@_)},
        '/save'         => sub{$self->save_config(@_)},
        '/view'         => sub{$self->send_index(@_)},
        '/stream'       => sub{$self->setup_stream(@_)},
        '/favicon.ico'  => sub{$self->not_found(@_)},
        '/say'          => sub{$self->handle_message(@_)},
        '/static/'      => sub{$self->handle_static(@_)},
        '/get/'         => sub{async_fetch($_[1],$_[0]->uri); return RC_WAIT;},
      },
      StreamHandler    => sub{$self->handle_stream(@_)},
    );
  }
  
  sub START {
    my $self = shift;
    POE::Kernel->delay(ping => 15);
  }

  event ping => sub {
    my $self = shift;
    my $data = {
      type  => "action",
      event => "ping",
    };
    push @{$_->{actions}}, $data for @{$self->streams};
    $_->continue for @{$self->streams};
    POE::Kernel->delay(ping => 15);
  };

  method config {
    return $self->app->config;
  }

  method check_authentication ($req, $res) {

    return RC_OK unless ($self->config->{auth}
        and ref $self->config->{auth} eq 'HASH'
        and $self->config->{auth}{username}
        and $self->config->{auth}{password});

    if (my $auth  = $req->header('authorization')) {
      $auth =~ s/^Basic //;
      $auth = decode_base64($auth);
      my ($user,$password)  = split(/:/, $auth);
      if ($self->config->{auth}{username} eq $user &&
          $self->config->{auth}{password} eq $password) {
        return RC_OK;
      }
      else {
        $self->log_debug("auth failed");
      }
    }
    $res->code(401);
    $res->header('WWW-Authenticate' => 'Basic realm="Alice"');
    $res->close();
    return RC_DENY;
  }

  method setup_stream ($req, $res) {

    # XHR tries to reconnect again with this header for some reason
    return 200 if defined $req->header('error');
    
    $req->header(Connection => 'close');
    $res->header(Connection => 'close');
    
    my $local_time = time;
    my $remote_time = $local_time;

    $self->log_debug("opening a streaming http connection");
    $res->streaming(1);
    $res->content_type('multipart/mixed; boundary=xalicex; charset=utf-8');
    $res->{msgs} = [];
    $res->{actions} = [ map {$_->nicks_action} $self->app->windows ];
    
    if ($req->uri->query_param('t')) {
      $remote_time = $req->uri->query_param('t')
    }
    $res->{offset} = $local_time - $remote_time;
    $self->log_debug("request time offset is " . $res->{offset});

    # populate the msg queue with any buffered messages
    if (defined (my $msgid = $req->uri->query_param('msgid'))) {
      $res->{msgs} = $self->app->buffered_messages($msgid);
    }
    push @{$self->streams}, $res;
    return 200;
  }

  method handle_stream ($req, $res) {
    if ($res->is_error) {
      $self->end_stream($res);
      return;
    }
    if (@{$res->{msgs}} or @{$res->{actions}}) {
      my $output;
      if (! $res->{started}) {
        $res->{started} = 1;
        $output .= $self->seperator."\n";
      }
      $output .= to_json({msgs => $res->{msgs}, actions => $res->{actions},
                          time => time - $res->{offset}});
      my $padding = " " x (1024 - bytes::length $output);
      $res->send($output . $padding . "\n" . $self->seperator . "\n");
      if ($res->is_error) {
        $self->end_stream($res);
        return;
      }
      else {
        $res->{msgs} = [];
        $res->{actions} = [];
        $res->continue;
      }
    }
  }

  method end_stream ($res) {
    $self->log_debug("closing a streaming http connection");
    for (0 .. scalar @{$self->streams} - 1) {
      if (! $self->streams->[$_] or ($res and $res == $self->streams->[$_])) {
        splice(@{$self->streams}, $_, 1);
      }
    }
    $res->close;
    $res->continue;
  }


  method handle_message ($req, $res) {
    my $msg  = $req->uri->query_param('msg');
    my $source = $req->uri->query_param('source');
    my $window = $self->app->get_window($source);
    return unless $window;
    for (split /\n/, $msg) {
      eval {$self->app->dispatch($_, $window) if length $_};
      if ($@) {$self->log_debug($@)}
    }
    return 200;
  }

  method handle_static ($req, $res) {
    my $file = $req->uri->path;
    my ($ext) = ($file =~ /[^\.]\.(.+)$/);
    if (-e $self->assetdir . "/$file") {
      open my $fh, '<', $self->assetdir . "/$file";
      $self->log_debug("serving static file: $file");
      if ($ext =~ /png|gif|jpg|jpeg/i) {
        $res->content_type("image/$ext"); 
      }
      elsif ($ext =~ /js/) {
        $res->header("Cache-control" => "no-cache");
        $res->content_type("text/javascript");
      }
      elsif ($ext =~ /css/) {
        $res->header("Cache-control" => "no-cache");
        $res->content_type("text/css");
      }
      else {
        $self->not_found($req, $res);
      }
      my @file = <$fh>;
      $res->content(join "", @file);
      return 200;
    }
    $self->not_found($req, $res);
  }

  method send_index ($req, $res) {
    $self->log_debug("serving index");
    $res->content_type('text/html; charset=utf-8');
    my $output = '';
    my $channels = [];
    for my $window (sort {$a->title cmp $b->title} $self->app->windows) {
      push @$channels, {
        window  => $window->serialized(encoded => 1),
        topic   => $window->topic,
      }
    }
    $self->tt->process('index.tt', {
      windows   => $channels,
      style     => $self->config->{style} || "default",
    }, \$output) or die $!;
    $res->content($output);
    return 200;
  }

  method send_config ($req, $res) {
    $self->log_debug("serving config");
    $res->header("Cache-control" => "no-cache");
    my $output = '';
    $self->tt->process('config.tt', {
      style       => $self->config->{style} || "default",
      config      => $self->config,
      connections => [ sort {$a->{alias} cmp $b->{alias}}
                       $self->app->connections ],
    }, \$output);
    $res->content($output);
    return 200;
  }

  method server_config ($req, $res) {
    $self->log_debug("serving blank server config");
    $res->header("Cache-control" => "no-cache");
    my $name = $req->uri->query_param('name');
    $self->log_debug($name);
    my $config = '';
    $self->tt->process('server_config.tt', {name => $name}, \$config);
    my $listitem = '';
    $self->tt->process('server_listitem.tt', {name => $name}, \$listitem);
    $res->content(to_json({config => $config, listitem => $listitem}));
    return 200;
  }

  method save_config ($req, $res) {
    $self->log_debug("saving config");
    my $new_config = {};
    my $servers;
    for my $name ($req->uri->query_param) {
      next unless $req->uri->query_param($name);
      if ($name =~ /^(.+?)_(.+)/) {
        if ($2 eq "channels" or $2 eq "on_connect") {
          $new_config->{$1}{$2} = [$req->uri->query_param($name)];
        }
        else {
          $new_config->{$1}{$2} = $req->uri->query_param($name);
        }
      }
    }
    for my $newserver (values %$new_config) {
      if (! exists $self->config->{servers}{$newserver->{name}}) {
        $self->app->add_irc_server($newserver->{name}, $newserver);
      }
      $self->config->{servers}{$newserver->{name}} = $newserver;
    }
    DumpFile($ENV{HOME}.'/.alice.yaml', $self->config);
  }

  method not_found ($req, $res) {
    $self->log_debug("serving 404:", $req->uri->path);
    $res->code(404);
    return 404;
  }

  method has_clients {
    return scalar @{$self->streams};
  }

  sub send {
    my ($self, @data) = @_;
    return unless $self->has_clients;
    for my $res (@{$self->streams}) {
      for my $item (@data) {
        if ($item->{type} eq "message") {
          push @{$res->{msgs}}, $item;
        }
        elsif ($item->{type} eq "action") {
          push @{$res->{actions}}, $item;
        }
      }
    }
    $_->continue for @{$self->streams};
  }

  sub log_debug {
    my $self = shift;
    print STDERR join " ", @_, "\n" if $self->config->{debug};
  }

  sub log_info {
    print STDERR join " ", @_, "\n";
  } 
  
  for my $method (qw/send_config save_config send_index
                  not_found handle_message handle_static server_config/) {
    Moose::Util::add_method_modifier(__PACKAGE__, "before", [$method, sub {
      $_[1]->header(Connection => 'close');
      $_[2]->header(Connection => 'close');
      $_[2]->streaming(0);
      $_[2]->code(200);
    }]);
    Moose::Util::add_method_modifier(__PACKAGE__, "after", [$method, sub {
      if (my $content = Compress::Zlib::memGzip($_[2]->content)) {
        $_[2]->header('Content-Encoding' => 'gzip');
        $_[2]->content($content)
      }
    }]);
  }
}
