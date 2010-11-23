package App::Alice::HTTPD;

use AnyEvent;
use AnyEvent::HTTP;

use Twiggy::Server;
use Plack::Request;
use Plack::Builder;
use Plack::Middleware::Static;
use Plack::Session::Store::File;
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
  [ "config"       => "send_config" ],
  [ "prefs"        => "send_prefs" ],
  [ "serverconfig" => "server_config" ],
  [ "save"         => "save_config" ],
  [ "tabs"         => "tab_order" ],
  [ "login"        => "login" ],
  [ "logout"       => "logout" ],
  [ "view"         => "send_index" ],
];

sub url_handlers { return $url_handlers }

my $ok = sub{ [200, ["Content-Type", "text/plain", "Content-Length", 2], ['ok']] };

sub BUILD {
  my $self = shift;
  $self->httpd;
  $self->ping;
}

sub _build_httpd {
  my $self = shift;
  my $httpd = Twiggy::Server->new(
    host => $self->config->http_address,
    port => $self->config->http_port,
  );
  $httpd->register_service(
    builder {
      if ($self->auth_enabled) {
        mkdir $self->config->path."/sessions"
          unless -d $self->config->path."/sessions";
        enable "Session",
          store => Plack::Session::Store::File->new(dir => $self->config->path),
          expires => "24h";
      }
      enable "Static", path => qr{^/static/}, root => $self->config->assetdir;
      enable "WebSocket";
      sub {$self->dispatch(shift)}
    }
  );
  $self->httpd($httpd);
}

sub dispatch {
  my ($self, $env) = @_;
  my $req = Plack::Request->new($env);
  if ($self->auth_enabled) {
    unless ($req->path eq "/login" or $self->is_logged_in($req)) {
      my $res = $req->new_response;
      if ($req->path eq "/") {
        $res->redirect("/login");
      } else {
        $res->status(401);
        $res->body("unauthorized");
      }
      return $res->finalize;
    }
  }
  for my $handler (@{$self->url_handlers}) {
    my $path = $handler->[0];
    if ($req->path_info =~ /^\/$path\/?$/) {
      my $method = $handler->[1];
      return $self->$method($req);
    }
  }
  return $self->not_found($req);
}

sub is_logged_in {
  my ($self, $req) = @_;
  my $session = $req->env->{"psgix.session"};
  return $session->{is_logged_in};
}

sub login {
  my ($self, $req) = @_;
  my $res = $req->new_response;
  if (!$self->auth_enabled or $self->is_logged_in($req)) {
    $res->redirect("/");
    return $res->finalize;
  }
  elsif (my $user = $req->parameters->{username}
     and my $pass = $req->parameters->{password}) {
    if ($self->authenticate($user, $pass)) {
      $req->env->{"psgix.session"} = {
        is_logged_in => 1,
        username     => $self->app->config->auth->{user},
        userid       => $self->app->user,
      };
      $res->redirect("/");
      return $res->finalize;
    }
    $res->body($self->render("login", "bad username or password"));
  }
  else {
    $res->body($self->render("login"));
  }
  $res->status(200);
  return $res->finalize;
}

sub logout {
  my ($self, $req) = @_;
  $_->close for @{$self->app->streams};
  my $res = $req->new_response;
  if (!$self->auth_enabled) {
    $res->redirect("/");
  } else {
    $req->env->{"psgix.session"}{is_logged_in} = 0;
    $req->env->{"psgix.session.options"}{expire} = 1;
    $res->redirect("/login");
  }
  return $res->finalize;
}

sub shutdown {
  my $self = shift;
  $self->httpd(undef);
}

sub setup_xhr_stream {
  my ($self, $req) = @_;
  my $app = $self->app;
  $app->log(info => "opening new stream");

  return sub {
    my $respond = shift;

    my $writer = $respond->([200, [@App::Alice::Stream::XHR::headers]]);
    my $stream = App::Alice::Stream::XHR->new(
      queue      => [ map({$_->join_action} $app->windows) ],
      writer     => $writer,
      start_time => $req->parameters->{t},
      # android requires 4K updates to trigger loading event
      min_bytes  => $req->user_agent =~ /android/i ? 4096 : 0,
      on_error => sub { $app->purge_disconnects },
    );

    $app->add_stream($stream);
    $app->update_stream($stream, $req->parameters);
  }
}

sub setup_ws_stream {
  my ($self, $req) = @_;
  my $app = $self->app;
  $app->log(info => "opening new websocket stream");

  return sub {
    my $respond = shift;

    if (my $fh = $req->env->{'websocket.impl'}->handshake) {
      my $stream = App::Alice::Stream::WebSocket->new(
        start_time => $req->parameters->{t} || time,
        fh      => $fh,
        on_read => sub { $app->handle_message(@_) },
        on_error => sub { $app->purge_disconnects },
      );
      $stream->send([ map({$_->join_action} $app->windows) ]);
      $app->add_stream($stream);
      $app->update_stream($stream, $req->parameters);
    }
    else {
      my $code = $req->env->{'websocket.impl'}->error_code;
      $respond->([$code, ["Content-Type", "text/plain"], ["something broke"]]);
    }
  };
}

sub handle_message {
  my ($self, $req) = @_;

  $self->app->handle_message({
    msg    => $req->parameters->{msg},
    html   => $req->parameters->{html},
    source => $req->parameters->{source}
  });
  
  return $ok->();
}

sub send_index {
  my ($self, $req) = @_;
  my $options = $self->merged_options($req);
  my $app = $self->app;

  return sub {
    my $respond = shift;
    my $writer = $respond->([200, ["Content-type" => "text/html; charset=utf-8"]]);
    my @windows = $app->sorted_windows;
    @windows > 1 ? $windows[1]->{active} = 1 : $windows[0]->{active} = 1;

    my @queue;
    
    push @queue, sub {$app->render('index_head', $options, @windows)};
    for my $window (@windows) {
      push @queue, sub {$app->render('window_head', $window)};
      push @queue, sub {$app->render('window_footer', $window)};
    }
    push @queue, sub {
      my $html = $app->render('index_footer', @windows);
      delete $_->{active} for @windows;
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
}

sub merged_options {
  my ($self, $req) = @_;
  my $config = $self->app->config;
  my $params = $req->parameters;
  my %options = (
   images => $req->parameters->{images} || $config->images,
   debug  => $req->parameters->{debug}  || ($config->show_debug ? 'true' : 'false'),
   timeformat => $req->parameters->{timeformat} || $config->timeformat,
  );
  join "&", map {"$_=$options{$_}"} keys %options;
}

sub send_config {
  my ($self, $req) = @_;
  $self->app->log(info => "serving config");
  my $output = $self->render('servers');
  my $res = $req->new_response(200);
  $res->body($output);
  return $res->finalize;
}

sub send_prefs {
  my ($self, $req) = @_;
  $self->app->log(info => "serving prefs");
  my $output = $self->render('prefs');
  my $res = $req->new_response(200);
  $res->body($output);
  return $res->finalize;
}

sub server_config {
  my ($self, $req) = @_;
  $self->app->log(info => "serving blank server config");
  
  my $name = $req->parameters->{name};
  $name =~ s/\s+//g;
  my $config = $self->render('new_server', $name);
  my $listitem = $self->render('server_listitem', $name);
  
  my $res = $req->new_response(200);
  $res->body(to_json({config => $config, listitem => $listitem}));
  $res->header("Cache-control" => "no-cache");
  return $res->finalize;
}

sub save_config {
  my ($self, $req) = @_;
  $self->app->log(info => "saving config");
  
  my $new_config = {};
  if ($req->parameters->{has_servers}) {
    $new_config->{servers} = {};
  }
  for my $name (keys %{$req->parameters}) {
    next unless $req->parameters->{$name};
    next if $name eq "has_servers";
    if ($name eq "highlights" or $name eq "monospace_nicks") {
      $new_config->{$name} = [$req->parameters->get_all($name)];
    }
    elsif ($name =~ /^(.+?)_(.+)/ and exists $new_config->{servers}) {
      if ($2 eq "channels" or $2 eq "on_connect") {
        $new_config->{servers}{$1}{$2} = [$req->parameters->get_all($name)];
      } else {
        $new_config->{servers}{$1}{$2} = $req->parameters->{$name};
      }
    }
    else {
      $new_config->{$name} = $req->parameters->{$name};
    }
  }
  $self->app->reload_config($new_config);

  $self->app->broadcast(
    $self->app->format_info("config", "saved")
  );

  return $ok->();
}

sub tab_order  {
  my ($self, $req) = @_;
  $self->app->log(debug => "updating tab order");
  
  $self->app->tab_order([grep {defined $_} $req->parameters->get_all('tabs')]);
  return $ok->();
}

sub not_found  {
  my ($self, $req) = @_;
  $self->app->log(debug => "sending 404 " . $req->path_info);
  my $res = $req->new_response(404);
  return $res->finalize;
}

sub auth_enabled {
  my $self = shift;
  $self->app->auth_enabled;
}

sub authenticate {
  my $self = shift;
  $self->app->authenticate(@_);
}

sub render {
  my $self = shift;
  return $self->app->render(@_);
}

__PACKAGE__->meta->make_immutable;
1;
