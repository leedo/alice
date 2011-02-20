package App::Alice::HTTPD;

use AnyEvent;
use AnyEvent::HTTP;

use Twiggy::Server;
use Plack::Request;
use Plack::Builder;
use Plack::Middleware::Static;
use Plack::Session::Store::File;
use App::Alice::Request;
use App::Alice::Stream::XHR;
use App::Alice::Stream::WebSocket;
use App::Alice::Commands;
use JSON;
use Encode;
use utf8;
use Any::Moose;

has app => (
  is  => 'ro',
  isa => 'App::Alice',
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

sub config {$_[0]->app->config}

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
    $httpd = Twiggy::Server->new(
      host => $self->config->http_address,
      port => $self->config->http_port,
    );
    $httpd->register_service(
      builder {
        if ($self->auth_enabled) {
          mkdir $self->config->path."/sessions"
            unless -d $self->config->path."/sessions";
          enable "Session",
            store => Plack::Session::Store::File->new(dir => $self->config->path."/sessions"),
            expires => "24h";
        }
        enable "Static", path => qr{^/static/}, root => $self->config->assetdir;
        enable "WebSocket";
        sub {
          my $env = shift;
          return sub {$self->dispatch($env, shift)}
        }
      }
    );
  };

  warn $@ if $@;
  return $httpd;
}

sub dispatch {
  my ($self, $env, $cb) = @_;

  my $req = App::Alice::Request->new($env, $cb);
  my $res = $req->new_response(200);

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

  if ($req->path eq "/") {
    $res->redirect("/login");
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

  # no auth is required
  if (!$self->auth_enabled) {
    $res->redirect("/");
    $res->send;
  }

  # we have credentials
  elsif (my $user = $req->param('username')
     and my $pass = $req->param('password')) {

    $self->authenticate($user, $pass, sub {
      my $success = shift;
      if ($success) {
        $req->env->{"psgix.session"} = {
          is_logged_in => 1,
          username     => $self->app->config->auth->{user},
          userid       => $self->app->user,
        };
        $res->redirect("/");
      }
      else {
        $req->env->{"psgix.session"}{is_logged_in} = 0;
        $req->env->{"psgix.session.options"}{expire} = 1;
        $res->body($self->render("login", "bad username or password"));
      }
      $res->send;
    });
  }

  # render the login page
  else {
    $res->body($self->render("login"));
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

sub shutdown {
  my $self = shift;
  $self->httpd(undef);
}

sub setup_xhr_stream {
  my ($self, $req, $res) = @_;
  my $app = $self->app;
  $app->log(info => "opening new stream");

  $res->headers([@App::Alice::Stream::XHR::headers]);
  my $stream = App::Alice::Stream::XHR->new(
    queue      => [ map({$_->join_action} $app->windows) ],
    writer     => $res->writer,
    start_time => $req->param('t'),
    # android requires 4K updates to trigger loading event
    min_bytes  => $req->user_agent =~ /android/i ? 4096 : 0,
    on_error => sub { $app->purge_disconnects },
  );

  $app->add_stream($stream);
  $app->update_stream($stream, $req);
}

sub setup_ws_stream {
  my ($self, $req, $res) = @_;
  my $app = $self->app;
  $app->log(info => "opening new websocket stream");

  if (my $fh = $req->env->{'websocket.impl'}->handshake) {
    my $stream = App::Alice::Stream::WebSocket->new(
      start_time => $req->param('t') || time,
      fh      => $fh,
      on_read => sub { $app->handle_message(@_) },
      on_error => sub { $app->purge_disconnects },
    );
    $stream->send([ map({$_->join_action} $app->windows) ]);
    $app->add_stream($stream);
    $app->update_stream($stream, $req);
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

  $self->app->handle_message({
    msg    => defined $msg ? $msg : "",
    html   => defined $html ? $html : "",
    source => defined $source ? $source : "",
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
    return $html;
  };

  my $idle_w; $idle_w = AE::idle sub {
    if (my $cb = shift @queue) {
      my $content = encode_utf8 $cb->();
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
  return {
   images => $req->param('images') || $config->images,
   avatars => $req->param('avatars') || $config->avatars,
   debug  => $req->param('debug')  || ($config->show_debug ? 'true' : 'false'),
   timeformat => $req->param('timeformat') || $config->timeformat,
   image_prefix => $req->param('image_prefix') || $config->image_prefix,
  };
}

sub template {
  my ($self, $req, $res) = @_;
  my $path = $req->path;
  $path =~ s/^\///;

  eval {
    my $body = $self->render($path);
    $res->body($self->render($path));
  };

  $@ ? $res->notfound : $res->send;
}

sub save_tabsets {
  my ($self, $req, $res) = @_;
  $self->app->log(info => "saving tabsets");

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
  $self->app->log(info => "serving blank server config");
  
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
  $self->app->log(info => "saving config");
  
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

  $self->app->broadcast(
    $self->app->format_info("config", "saved")
  );

  $res->ok;
}

sub tab_order  {
  my ($self, $req, $res) = @_;
  $self->app->log(debug => "updating tab order");
  
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
  $cb->($success);
}

sub render {
  my $self = shift;
  return $self->app->render(@_);
}

sub export_config {
  my ($self, $req, $res) = @_;
  $res->content_type("text/plain");
  {
    $res->body(to_json($self->app->config->serialized,
      {utf8 => 1, pretty => 1}));
  }
  $res->send;
}

__PACKAGE__->meta->make_immutable;
1;
