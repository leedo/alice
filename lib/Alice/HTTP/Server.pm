package Alice::HTTP::Server;

use AnyEvent;
use AnyEvent::HTTP;

use Fliggy::Server;
use Plack::Builder;
use Plack::Middleware::Static;
use Plack::Session::Store::File;
use Plack::Session::State::Cookie;

use Alice::HTTP::Request;
use Alice::HTTP::Stream::XHR;
use Alice::HTTP::Stream::WebSocket;

use JSON;
use Encode;
use Any::Moose;

has app => (
  is  => 'ro',
  isa => 'Alice',
  required => 1,
);

has httpd => (
  is  => 'rw',
  lazy => 1,
  builder => "_build_httpd",
);

has ping => (
  is  => 'rw',
  lazy => 1,
  default => sub {
    my $self = shift;
    AE::timer 1, 5, sub {
      $self->app->ping;
    };
  },
);

has port => (
  is => 'ro',
  default => 8080,
);

has address => (
  is => 'ro',
  default => "127.0.0.1",
);

has session => (
  is => 'ro'
);

has assets => (
  is => 'ro',
  required => 1,
);

my $url_handlers = [
  [ "say"          => "handle_message" ],
  [ "stream"       => "setup_xhr_stream" ],
  [ "wsstream"     => "setup_ws_stream" ],
  [ ""             => "send_index" ],
  [ "safe"         => "send_safe_index" ],
  [ "tabs"         => "tab_order" ],
  [ "savetabsets"  => "save_tabsets" ],
  [ "serverconfig" => "server_config" ],
  [ "save"         => "save_config" ],
  [ "login"        => "login" ],
  [ "logout"       => "logout" ],
  [ "export"       => "export_config" ],
];

sub url_handlers { return $url_handlers }

sub BUILD {
  my $self = shift;
  $self->httpd;
  $self->ping;
}

sub _build_httpd {
  my $self = shift;
  my $httpd;

  # eval in case server can't bind port
  eval {
    $httpd = Fliggy::Server->new(
      host => $self->address,
      port => $self->port,
    );
    $httpd->register_service(
      builder {
        enable "Session",
          store => $self->session,
          state => Plack::Session::State::Cookie->new(expires => 60 * 60 * 24 * 7);
        enable "Static", path => qr{^/static/}, root => $self->assets;
        enable "+Alice::HTTP::WebSocket";
        sub {
          my $env = shift;
          return sub {$self->dispatch($env, shift)}
        }
      }
    );
  };

  AE::log(warn => $@) if $@;
  return $httpd;
}

sub dispatch {
  my ($self, $env, $cb) = @_;

  my $req = Alice::HTTP::Request->new($env, $cb);
  my $res = $req->new_response(200);

  AE::log trace => $req->path;

  if ($self->auth_enabled) {
    unless ($req->path eq "/login" or $self->is_logged_in($req)) {
      $self->auth_failed($req, $res);
      return;
    }
  }
  for my $handler (@{$self->url_handlers}) {
    my $path = $handler->[0];
    if ($req->path_info =~ /^\/$path\/?$/) {
      my $method = $handler->[1];
      $self->$method($req, $res);
      return;
    }
  }
  $self->template($req, $res);
}

sub auth_failed {
  my ($self, $req, $res) = @_;

  if ($req->path =~ m{^(/(?:safe)?)$}) {
    $res->redirect("/login".($1 ? "?dest=$1" : ""));
    $res->body("bai");
  } else {
    $res->status(401);
    $res->body("unauthorized");
  }
  $res->send;
}

sub is_logged_in {
  my ($self, $req) = @_;
  my $session = $req->env->{"psgix.session"};
  return $session->{is_logged_in};
}

sub login {
  my ($self, $req, $res) = @_;

  my $dest = $req->param("dest") || "/";

  # no auth is required
  if (!$self->auth_enabled) {
    $res->redirect($dest);
    $res->send;
  }

  # we have credentials
  elsif (my $user = $req->param('username')
     and my $pass = $req->param('password')) {

    $self->authenticate($user, $pass, sub {
      my $app = shift;
      if ($app) {
        $req->env->{"psgix.session"} = {
          is_logged_in => 1,
          username     => $user,
          userid       => $app->user,
        };
        $res->redirect($dest);
      }
      else {
        $req->env->{"psgix.session"}{is_logged_in} = 0;
        $req->env->{"psgix.session.options"}{expire} = 1;
        $res->content_type("text/html; charset=utf-8");
        $res->body($self->render("login", $dest, "bad username or password"));
      }
      $res->send;
    });
  }

  # render the login page
  else {
    $res->content_type("text/html; charset=utf-8");
    $res->body($self->render("login", $dest));
    $res->send;
  }
}

sub logout {
  my ($self, $req, $res) = @_;
  $_->close for @{$self->app->streams};
  if (!$self->auth_enabled) {
    $res->redirect("/");
  } else {
    $req->env->{"psgix.session"}{is_logged_in} = 0;
    $req->env->{"psgix.session.options"}{expire} = 1;
    $res->redirect("/login");
  }
  $res->send;
}

sub setup_xhr_stream {
  my ($self, $req, $res) = @_;
  my $app = $self->app;

  AE::log debug => "opening new stream";

  $res->headers([@Alice::HTTP::Stream::XHR::headers]);
  my $stream = Alice::HTTP::Stream::XHR->new(
    writer     => $res->writer,
    start_time => $req->param('t'),
    # android requires 4K updates to trigger loading event
    min_bytes  => $req->user_agent =~ /android/i ? 4096 : 0,
    on_error => sub { $app->purge_disconnects },
  );

  $stream->send([$app->connect_actions]);
  $app->add_stream($stream);
}

sub setup_ws_stream {
  my ($self, $req, $res) = @_;
  my $app = $self->app;

  AE::log debug => "opening new websocket stream";

  if (my $fh = $req->env->{'websocket.impl'}->handshake) {
    my $stream = Alice::HTTP::Stream::WebSocket->new(
      start_time => $req->param('t') || time,
      fh      => $fh,
      on_read => sub { $app->handle_message(@_) },
      on_error => sub { $app->purge_disconnects },
      ws_version => $req->env->{'websocket.impl'}->version,
    );

    $stream->send([$app->connect_actions]);
    $app->add_stream($stream);
  }
  else {
    my $code = $req->env->{'websocket.impl'}->error_code;
    $res->send([$code, ["Content-Type", "text/plain"], ["something broke"]]);
  }
}

sub handle_message {
  my ($self, $req, $res) = @_;

  my $msg = $req->param('msg');
  my $html = $req->param('html');
  my $source = $req->param('source');
  my $stream = $req->param('stream');

  $self->app->handle_message({
    msg    => defined $msg ? $msg : "",
    html   => defined $html ? $html : "",
    source => defined $source ? $source : "",
    stream => defined $stream ? $stream : "",
  });
  
  $res->ok;
}

sub send_safe_index {
  my ($self, $req, $res) = @_;
  $req->parameters->{images} = "hide";
  $req->parameters->{avatars} = "hide";
  $self->send_index($req, $res);
}

sub send_index {
  my ($self, $req, $res) = @_;
  my $options = $self->merged_options($req);
  my $app = $self->app;

  $res->headers(["Content-type" => "text/html; charset=utf-8"]);
  my $writer = $res->writer;
  my @windows = $app->sorted_windows;

  my @queue;
    
  push @queue, sub {$app->render('index_head', @windows)};
  for my $window (@windows) {
    push @queue, sub {$app->render('window_head', $window)};
    push @queue, sub {$app->render('window_footer', $window)};
  }
  push @queue, sub {
    my $html = $app->render('index_footer', $options, @windows);
    $app->config->first_run(0);
    $app->config->write;
    return $html;
  };

  my $idle_w; $idle_w = AE::idle sub {
    if (my $cb = shift @queue) {
      my $content = encode "utf8", $cb->();
      $writer->write($content);
    } else {
      $writer->close;
      undef $idle_w;
    }
  };
}

sub merged_options {
  my ($self, $req) = @_;
  my $config = $self->app->config;

  my $options = { map { $_ => ($req->param($_) || $config->$_) }
      qw/images avatars alerts audio timeformat image_prefix/ };

  if ($options->{images} eq "show" and $config->animate eq "hide") {
    $options->{image_prefix} = "https://noembed.com/i/still/";
  }

  return $options;
}

sub template {
  my ($self, $req, $res) = @_;
  my $path = $req->path;
  $path =~ s/^\///;

  eval {
    $res->body($self->render($path));
  };

  if ($@) {
    AE::log(warn => $@);
    $res->notfound;
  }
  else {
    $res->send;
  }
}

sub save_tabsets {
  my ($self, $req, $res) = @_;

  AE::log debug => "saving tabsets";

  my $tabsets = {};

  for my $set ($req->param) {
    next if $set eq '_';
    my $wins = [$req->param($set)];
    $tabsets->{$set} = $wins->[0] eq 'empty' ? [] : $wins;
  }

  $self->app->config->tabsets($tabsets);
  $self->app->config->write;

  $res->body($self->render('tabset_menu'));
  $res->send;
}

sub server_config {
  my ($self, $req, $res) = @_;

  AE::log debug => "serving blank server config";
  
  my $name = $req->param('name');
  $name =~ s/\s+//g;
  my $config = $self->render('new_server', $name);
  my $listitem = $self->render('server_listitem', $name);
  
  $res->body(to_json({config => $config, listitem => $listitem}));
  $res->header("Cache-control" => "no-cache");
  $res->send;
}

#
# TODO separate methods for saving prefs and server configs
#

sub save_config {
  my ($self, $req, $res) = @_;

  AE::log debug => "saving config";
  
  my $new_config = {};
  if ($req->param('has_servers')) {
    $new_config->{servers} = {};
  }
  else {
    $new_config->{$_} = [$req->param($_)] for qw/highlights monospace_nicks/;
  }

  for my $name ($req->param) {
    next unless $req->param($name);
    next if $name =~ /^(?:has_servers|highlights|monospace_nicks)$/;
    if ($name =~ /^(.+?)_(.+)/ and exists $new_config->{servers}) {
      if ($2 eq "channels" or $2 eq "on_connect") {
        $new_config->{servers}{$1}{$2} = [$req->param($name)];
      } else {
        $new_config->{servers}{$1}{$2} = $req->param($name);
      }
    }
    else {
      $new_config->{$name} = $req->param($name);
    }
  }

  $self->app->reload_config($new_config);
  $self->app->send_info("config", "saved");
  $res->ok;
}

sub tab_order  {
  my ($self, $req, $res) = @_;

  AE::log debug => "updating tab order";
  
  $self->app->tab_order([grep {defined $_} $req->param('tabs')]);
  $res->ok;
}

sub auth_enabled {
  my $self = shift;
  $self->app->auth_enabled;
}

sub authenticate {
  my ($self, $user, $pass, $cb) = @_;
  my $success = $self->app->authenticate($user, $pass);
  $cb->($success ? $self->app : ());
}

sub render {
  my $self = shift;
  return $self->app->render(@_);
}

sub export_config {
  my ($self, $req, $res) = @_;
  $res->content_type("text/plain; charset=utf-8");
  {
    $res->body(to_json($self->app->config->serialized,
      {utf8 => 1, pretty => 1}));
  }
  $res->send;
}

__PACKAGE__->meta->make_immutable;
1;
