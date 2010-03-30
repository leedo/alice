package App::Alice::HTTPD;

use AnyEvent;
use AnyEvent::HTTP;

use Twiggy::Server;
use Plack::Request;
use Plack::Builder;
use Plack::Middleware::Static;
use Plack::Middleware::Auth::Basic;

use App::Alice::Stream;
use App::Alice::Commands;

use JSON;
use Encode;
use Any::Moose;
use Try::Tiny;

has 'app' => (
  is  => 'ro',
  isa => 'App::Alice',
  required => 1,
);

has 'httpd' => (is  => 'rw');
has 'ping_timer' => (is  => 'rw');

has 'config' => (
  is => 'ro',
  isa => 'App::Alice::Config',
  lazy => 1,
  default => sub {shift->app->config},
);

has 'url_handlers' => (
  is => 'ro',
  isa => 'ArrayRef',
  default => sub {
    [
      { re => qr{^/serverconfig/?$}, sub  => 'server_config' },
      { re => qr{^/config/?$},       sub  => 'send_config' },
      { re => qr{^/save/?$},         sub  => 'save_config' },
      { re => qr{^/tabs/?$},         sub  => 'tab_order' },
      { re => qr{^/view/?$},         sub  => 'send_index' },
      { re => qr{^/stream/?$},       sub  => 'setup_stream' },
      { re => qr{^/say/?$},          sub  => 'handle_message' },
      { re => qr{^/get},             sub  => 'image_proxy' },
      { re => qr{^/logs/?$},         sub  => 'send_logs' },
      { re => qr{^/search/?$},       sub  => 'send_search' },
      { re => qr{^/range/?$},        sub  => 'send_range' },
      { re => qr{^/$},               sub  => 'send_index' },
    ]
  }
);

has 'streams' => (
  is => 'rw',
  auto_deref => 1,
  isa => 'ArrayRef[App::Alice::Stream]',
  default => sub {[]},
);

sub add_stream {push @{shift->streams}, @_}
sub no_streams {@{$_[0]->streams} == 0}
sub stream_count {scalar @{$_[0]->streams}}

sub BUILD {
  my $self = shift;
  my $httpd = Twiggy::Server->new(
    host => $self->config->http_address,
    port => $self->config->http_port,
  );
  $httpd->register_service(
    builder {
      enable "Auth::Basic", authenticator => sub {$self->authenticate(@_)}
        if $self->app->config->auth_enabled;
      enable "Static", path => qr{^/static/}, root => $self->config->assetdir;
      sub {$self->dispatch(shift)}
    }
  );
  $self->httpd($httpd);
  $self->ping;
}

sub dispatch {
  my ($self, $env) = @_;
  my $req = Plack::Request->new($env);
  for my $handler (@{$self->url_handlers}) {
    my $re = $handler->{re};
    if ($req->path_info =~ /$re/) {
      my $sub = $handler->{sub};
      if ($self->meta->find_method_by_name($sub)) {
        return $self->$sub($req);
      }
    }
  }
  return $self->not_found($req);
}

sub ping {
  my $self = shift;
  $self->ping_timer(AnyEvent->timer(
    after    => 5,
    interval => 10,
    cb       => sub {
      $self->broadcast({
        type => "action",
        event => "ping",
      });
    }
  ));
}

sub shutdown {
  my $self = shift;
  $_->close for $self->streams;
  $self->streams([]);
  $self->ping_timer(undef);
  $self->httpd(undef);
}

sub image_proxy {
  my ($self, $req) = @_;
  my $url = $req->request_uri;
  $url =~ s/^\/get\///;
  return sub {
    my $respond = shift;
    http_get $url, sub {
      my ($data, $headers) = @_;
      my $res = $req->new_response($headers->{Status});
      $res->headers($headers);
      $res->body($data);
      $respond->($res->finalize);
    };
  }
}

sub broadcast {
  my ($self, @data) = @_;
  return if $self->no_streams or !@data;
  my $purge = 0;
  for my $stream ($self->streams) {
    try {
      $stream->send(@data);
    } catch {
      $stream->close;
      $purge = 1;
    };
  }
  $self->purge_disconnects if $purge;
};

sub authenticate {
  my ($self, $user, $pass) = @_;
  return 1 unless ($self->app->config->auth_enabled);

  if ($self->config->auth->{username} eq $user &&
      $self->config->auth->{password} eq $pass) {
    return 1;
  }
  return 0;
}

sub setup_stream {
  my ($self, $req) = @_;
  $self->app->log(info => "opening new stream");
  my $min = $req->param('msgid') || 0;
  return sub {
    my $respond = shift;
    my $stream = App::Alice::Stream->new(
      queue      => [ map({$_->join_action} $self->app->windows) ],
      writer     => $respond,
      start_time => $req->param('t'),
    );
    $self->add_stream($stream);
    $self->app->with_buffers(sub {
      return unless @_;
      $stream->enqueue(
        map  {$_->{buffered} = 1; $_}
        grep {$_->{msgid} > $min or $min > $self->app->msgid}
        @_
      );
      $stream->send(1); # force
    });
  }
}

sub purge_disconnects {
  my ($self) = @_;
  $self->app->log(debug => "removing broken streams");
  $self->streams([grep {!$_->closed} $self->streams]);
}

sub handle_message {
  my ($self, $req) = @_;
  my $msg  = $req->param('msg');
  utf8::decode($msg);
  my $source = $req->param('source');
  my $window = $self->app->get_window($source);
  if ($window) {
    for (split /\n/, $msg) {
      eval {$self->app->handle_command($_, $window) if length $_};
      if ($@) {$self->app->log(info => $@)}
    }
  }
  my $res = $req->new_response(200);
  $res->body('ok');
  return $res->finalize;
}

sub send_index {
  my ($self, $req) = @_;
  return sub {
    my $respond = shift;
    my $writer = $respond->([200, ["Content-type" => "text/html; charset=utf-8"]]);
    $writer->write(encode_utf8 $self->app->render('index_head'));
    my @windows = $self->app->sorted_windows;
    for (0 .. scalar @windows - 1) {
      my @classes;
      if (scalar @windows > 1 and $_ == 1) {
        push @classes, "active";
      } elsif (scalar @windows == 1 and $_ == 0) {
        push @classes, "active";
      }
      $writer->write(encode_utf8 $self->app->render('window', $windows[$_], @classes));
    }
    $writer->write(encode_utf8 $self->app->render('index_footer'));
    $writer->close;
  }
}

sub send_logs {
  my ($self, $req) = @_;
  my $output = $self->app->render('logs');
  my $res = $req->new_response(200);
  $res->body(encode_utf8 $output);
  return $res->finalize;
}

sub send_search {
  my ($self, $req) = @_;
  return sub {
    my $respond = shift;
    $self->app->history->search(%{$req->parameters}, sub {
      my $rows = shift;
      my $content = $self->app->render('results', $rows);
      my $res = $req->new_response(200);
      $res->body(encode_utf8 $content);
      $respond->($res->finalize);
    });
  }
}

sub send_range {
  my ($self, $req) = @_;
  return sub {
    my $respond = shift;
    $self->app->history->range($req->param('channel'), $req->param('time'), sub {
      my ($before, $after) = @_;
      $before = $self->app->render('range', $before, 'before');
      $after = $self->app->render('range', $after, 'after');
      my $res = $req->new_response(200);
      $res->body(to_json [$before, $after]);
      $respond->($res->finalize);
    }); 
  }
}

sub send_config {
  my ($self, $req) = @_;
  $self->app->log(info => "serving config");
  
  my $output = $self->app->render('servers');
  
  my $res = $req->new_response(200);
  $res->body($output);
  return $res->finalize;
}

sub server_config {
  my ($self, $req) = @_;
  $self->app->log(info => "serving blank server config");
  
  my $name = $req->param('name');
  $name =~ s/\s+//g;
  my $config = $self->app->render('new_server', $name);
  my $listitem = $self->app->render('server_listitem', $name);
  
  my $res = $req->new_response(200);
  $res->body(to_json({config => $config, listitem => $listitem}));
  $res->header("Cache-control" => "no-cache");
  return $res->finalize;
}

sub save_config {
  my ($self, $req) = @_;
  $self->app->log(info => "saving config");
  
  my $new_config = {servers => {}};
  
  for my $name (keys %{$req->parameters}) {
    next unless $req->parameters->{$name};
    if ($name =~ /^(.+?)_(.+)/) {
      if ($2 eq "channels" or $2 eq "on_connect") {
        $new_config->{servers}{$1}{$2} = [$req->parameters->get_all($name)];
      } else {
        $new_config->{servers}{$1}{$2} = $req->param($name);
      }
    } else {
      $new_config->{$name} = $req->param($name);
    }
  }
  
  $self->config->merge($new_config);
  $self->app->reload_config();
  $self->config->write;
  
  my $res = $req->new_response(200);
  $res->body('ok');
  return $res->finalize;
}

sub tab_order  {
  my ($self, $req) = @_;
  $self->app->log(debug => "updating tab order");
  
  $self->app->tab_order([grep {defined $_} $req->parameters->get_all('tabs')]);
  
  my $res = $req->new_response(200);
  $res->body('ok');
  return $res->finalize;
}

sub not_found  {
  my ($self, $req) = @_;
  $self->app->log(debug => "sending 404 " . $req->path_info);
  my $res = $req->new_response(404);
  return $res->finalize;
}

__PACKAGE__->meta->make_immutable;
1;
