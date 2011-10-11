package Alice::Role::HTTPRoutes;

use Any::Moose 'Role';
use Alice::Stream::XHR;
use Alice::Stream::WebSocket;
use JSON;
use Encode;
use Try::Tiny;

requires 'render';

our @ROUTES;

sub http_request {
  my ($self, $req, $res) = @_;

  for my $route (@ROUTES) {
    my $path = $route->[0];
    if ($req->path_info =~ /^\/$path\/?$/) {
      try {
        $route->[1]->($self, $req, $res);
      }
      catch {
        warn $_;
        $res->send([500, ["Content-Type", "text/plain"], ["something went wrong"]]);
      };
      return;
    }
  }
}

sub route {
  my ($path, $cb) = @_;
  push @ROUTES, [$path, $cb];
}

sub merged_options {
  my ($self, $req) = @_;
  return {
   images => $req->param('images') || $self->config->images,
   avatars => $req->param('avatars') || $self->config->avatars,
   debug  => $req->param('debug')  || ($self->config->show_debug ? 'true' : 'false'),
   timeformat => $req->param('timeformat') || $self->config->timeformat,
   image_prefix => $req->param('image_prefix') || $self->config->image_prefix,
  };
}

route say => sub {
  my ($self, $req, $res) = @_;

  my $msg = $req->param('msg');
  my $html = $req->param('html');
  my $source = $req->param('source');

  $self->handle_message({
    msg    => defined $msg ? $msg : "",
    html   => defined $html ? $html : "",
    source => defined $source ? $source : "",
  });
  
  $res->ok;
};

route stream => sub {
  my ($self, $req, $res) = @_;
  $self->log(info => "opening new stream");

  $res->headers([@Alice::Stream::XHR::headers]);
  my $stream = Alice::Stream::XHR->new(
    queue      => [ map({$_->join_action} $self->windows) ],
    writer     => $res->writer,
    start_time => $req->param('t'),
    # android requires 4K updates to trigger loading event
    min_bytes  => $req->user_agent =~ /android/i ? 4096 : 0,
    on_error => sub { $self->purge_disconnects },
  );

  $self->add_stream($stream);
  $self->update_stream($stream, $req);
};

route wsstream => sub {
  my ($self, $req, $res) = @_;
  $self->log(debug => "opening new websocket stream");

  if (my $fh = $req->env->{'websocket.impl'}->handshake) {
    my $stream = Alice::Stream::WebSocket->new(
      start_time => $req->param('t') || time,
      fh      => $fh,
      on_read => sub { $self->handle_message(@_) },
      on_error => sub { $self->purge_disconnects },
      ws_version => $req->env->{'websocket.impl'}->version,
    );
    $stream->send([ map({$_->join_action} $self->windows) ]);
    $self->add_stream($stream);
    $self->update_stream($stream, $req);
  }
  else {
    my $code = $req->env->{'websocket.impl'}->error_code;
    $res->send([$code, ["Content-Type", "text/plain"], ["something broke"]]);
  }
};

route "" => sub {
  my ($self, $req, $res) = @_;
  my $options = $self->merged_options($req);

  $res->headers(["Content-type" => "text/html; charset=utf-8"]);
  my $writer = $res->writer;
  my @windows = $self->sorted_windows;

  my @queue;
    
  push @queue, sub {$self->render('index_head', @windows)};
  push @queue, map {my $window = $_; sub {$self->render('window', $window)}} @windows;

  push @queue, sub {
    my $html = $self->render('index_footer', $options, @windows);
    if ($self->config->first_run) {
      $self->config->first_run(0);
      $self->config->write;
    }
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
};

route safe => sub {
  my ($self, $req, $res) = @_;
  $req->parameters->{images} = "hide";
  $req->parameters->{avatars} = "hide";
  $req->env->{PATH_INFO} = "/";
  $self->http_request($req, $res);
};

route tabsets => sub {
  my ($self, $req, $res) = @_;

  $res->body($self->render("tabsets"));
  $res->send;
};

route savetabsets => sub {
  my ($self, $req, $res) = @_;
  $self->log(info => "saving tabsets");

  my $tabsets = {};

  for my $set ($req->param) {
    next if $set eq '_';
    my $wins = [$req->param($set)];
    $tabsets->{$set} = $wins->[0] eq 'empty' ? [] : $wins;
  }

  $self->tabsets($tabsets);
  $self->writeconfig;

  $res->body($self->render('tabset_menu'));
  $res->send;
};

route serverconfig => sub {
  my ($self, $req, $res) = @_;
  $self->log(debug => "serving blank server config");
  
  my $name = $req->param('name');
  $name =~ s/\s+//g;
  my $config = $self->render('new_server', $name);
  my $listitem = $self->render('server_listitem', $name);
  
  $res->body(to_json({config => $config, listitem => $listitem}));
  $res->header("Cache-control" => "no-cache");
  $res->send;
};

#
# TODO separate methods for saving prefs and server configs
#

route save => sub {
  my ($self,  $req, $res) = @_;
  $self->log(info => "saving config");
  
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

  $self->reload_config($new_config);
  $self->log(info => "config saved");

  $res->ok;
};

route tabs => sub {
  my ($self, $req, $res) = @_;
  $self->log(debug => "updating tab order");
  
  $self->tab_order([grep {defined $_} $req->param('tabs')]);
  $res->ok;
};

route login => sub {
  my ($self, $req, $res) = @_;

  my $dest = $req->param("dest") || "/";

  # if a post made it here auth failed
  if ($req->method eq "POST") {
    $res->body($self->render("login", $dest, "bad username or password"));
  }
  else {
    $res->body($self->render("login", $dest));
  }
  $res->send;
};

route logout => sub {
  my ($self, $req, $res) = @_;
  $_->close for @{$self->streams};
  if (!$self->auth_enabled) {
    $res->redirect("/");
  } else {
    $req->env->{"psgix.session"}{is_logged_in} = 0;
    $req->env->{"psgix.session.options"}{expire} = 1;
    $res->redirect("/login");
  }
  $res->send;
};

route qr/.*/ => sub {
  my ($self, $req, $res) = @_;
  my $path = $req->path;
  $path =~ s/^\///;

  try {
    $res->body($self->render($path));
    $res->send;
  }
  catch {
    $res->notfound;
  };
};

route export => sub {
  my ($self, $req, $res) = @_;
  $res->content_type("text/plain; charset=utf-8");
  {
    $res->body(to_json($self->serialized,
      {utf8 => 1, pretty => 1}));
  }
  $res->send;
};

1;
