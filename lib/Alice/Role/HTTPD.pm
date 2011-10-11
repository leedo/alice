package Alice::Role::HTTPD;

use AnyEvent;

use Any::Moose 'Role';

use Plack::Builder;
use Plack::Middleware::Static;
use Plack::Session::Store::File;
use Plack::Session::State::Cookie;

use Alice::HTTP::Middleware::WebSocket;
use Alice::HTTP::Request;
use Alice::Stream;

use Encode;
use Try::Tiny;

our $SERVER = "Feersum";
eval "use $SERVER;";
if ($@) {
  warn "$SERVER server not found, using Twiggy instead\n";
  $SERVER = "Twiggy";
}

with "Alice::Role::HTTPD::$SERVER";

has httpd => (
  is  => 'rw',
  lazy => 1,
  builder => "_build_httpd",
);

sub _build_httpd {
  my $self = shift;

  # eval in case server can't bind port
  try {
    $self->httpd($self->build_httpd);
  }
  catch {
    warn "Error: could not start http server\n";
    warn "$_" if $_;
    exit 0;
  };

  $self->register_app($self->_build_app);
}

sub dispatch {
  my ($self, $env, $cb) = @_;

  my $req = Alice::HTTP::Request->new($env, $cb);
  my $res = $req->new_response(200);

  if ($self->auth_enabled) {
    if ($req->path eq "/login") {
      $self->handle_login($req, $res);
      return;
    }
    elsif (!$self->is_logged_in($req)) {
      $self->auth_failed($req, $res);
      return;
    }
  }

  return $self->http_request($req, $res);
}

sub handle_login {
  my ($self, $req, $res) = @_;

  my $user = $req->param("username") || "";
  my $pass = $req->param("password") || "";

  if ($req->method eq "POST") {
    $self->authenticate($user, $pass, sub {
      my $success = shift;
      if ($success) {
        $req->env->{"psgix.session"} = {
          is_logged_in => 1, 
          username     => $user,
          userid       => $self->user,
        };

        my $dest = $req->param("dest") || "/";
        $res->redirect($dest);
        $res->send;
      }
      else {
        $req->env->{"psgix.session"}{is_logged_in} = 0;
        $req->env->{"psgix.session.options"}{expire} = 1;
        $self->http_request($req, $res);
      }
    });
  }
  else {
    $self->http_request($req, $res);
  }
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

sub _build_app {
  my $self = shift;

  builder {
    if ($self->auth_enabled) {
      my $session = $self->configdir."/sessions";
      mkdir $session unless -d $session;
      enable "Session",
        store => Plack::Session::Store::File->new(dir => $session),
        state => Plack::Session::State::Cookie->new(expires => 60 * 60 * 24 * 7);
    }
    enable "ContentLength";
    enable "Static", path => qr{^/static/}, root => $self->config->assetdir;
    enable "+Alice::HTTP::Middleware::WebSocket";
    sub {
      my $env = shift;
      return sub {
        $self->dispatch($env, shift);
      }
    }
  }
}

1;
