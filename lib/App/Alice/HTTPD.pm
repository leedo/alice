package App::Alice::HTTPD;

use AnyEvent;
use Twiggy::Server;
use Plack::Request;
use Plack::Middleware::Static;
use AnyEvent::HTTP;
use App::Alice::Stream;
use App::Alice::CommandDispatch;
use MIME::Base64;
use JSON;
use Encode;
use Any::Moose;
use Try::Tiny;

use feature 'switch';

has 'app' => (
  is  => 'ro',
  isa => 'App::Alice',
  required => 1,
);

has 'httpd' => (
  is  => 'rw',
  isa => 'Twiggy::Server|Undef'
);

has 'streams' => (
  is  => 'rw',
  auto_deref => 1,
  isa => 'ArrayRef[App::Alice::Stream]',
  default => sub {[]},
);

sub add_stream {push @{shift->streams}, @_}
sub no_streams {@{$_[0]->streams} == 0}
sub stream_count {scalar @{$_[0]->streams}}

has 'config' => (
  is => 'ro',
  isa => 'App::Alice::Config',
  lazy => 1,
  default => sub {shift->app->config},
);

has 'ping_timer' => (
  is  => 'rw',
);

sub BUILD {
  my $self = shift;
  my $httpd = Twiggy::Server->new(
    host => $self->config->http_address,
    port => $self->config->http_port,
  );
  my $static = Plack::Middleware::Static->new(
    path => qr{^/static/},
    root => $self->config->assetdir,
  );
  $httpd->register_service($static->wrap(sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    given ($req->path_info) {
      when ('/serverconfig') {return $self->server_config($req)}
      when ('/config')       {return $self->send_config($req)}
      when ('/save')         {return $self->save_config($req)}
      when ('/tabs')         {return $self->tab_order($req)}
      when ('/view')         {return $self->send_index($req)}
      when ('/stream')       {return $self->setup_stream($req)}
      when ('/favicon.ico')  {return $self->not_found($req)}
      when ('/say')          {return $self->handle_message($req)}
      when ('/get')          {return $self->image_proxy($req)}
      when ('/logs')         {return $self->send_logs($req)}
      when ('/search')       {return $self->send_search($req)}
      when ('/range')        {return $self->send_range($req)}
      when ('/')             {return $self->send_index($req)}
      default                {return $self->not_found($req)}
    }
  }));
  $self->httpd($httpd);
  $self->ping;
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
  http_get $url, sub {
    my ($data, $headers) = @_;
    $req->respond([$headers->{Status},$headers->{Reason},$headers,$data]);
  };
}

sub broadcast {
  my ($self, @data) = @_;
  return if $self->no_streams or !@data;
  for my $stream ($self->streams) {
    $stream->enqueue(@data);
    try {
      $stream->broadcast;
    } catch {
      $stream->close;
      $self->purge_disconnects;
    };
  }
};

sub check_authentication {
  my ($self, $req) = @_;
  return unless ($self->config->auth
      and ref $self->config->auth eq 'HASH'
      and $self->config->auth->{username}
      and $self->config->auth->{password});

  if (my $auth  = $req->headers->{authorization}) {
    $auth =~ s/^Basic //;
    $auth = decode_base64($auth);
    my ($user,$password)  = split(/:/, $auth);
    if ($self->config->auth->{username} eq $user &&
        $self->config->auth->{password} eq $password) {
      return;
    }
    else {
      $self->app->log(info => "auth failed");
    }
  }
  $req->respond([401, 'unauthorized', {'WWW-Authenticate' => 'Basic realm="Alice"'}]);
}

sub setup_stream {
  my ($self, $req) = @_;
  $self->app->log(info => "opening new stream");
  my $msgid = $req->param('msgid') || 0;
  return sub {
    my $respond = shift;
    $self->add_stream(
      App::Alice::Stream->new(
        queue   => [
          map {$_->nicks_action} $self->app->windows
        ],
        writer => $respond,
        start_time => $req->param('t'),
        on_disconnect => sub {$self->purge_disconnects}
      )
    );
  }
}

sub purge_disconnects {
  my ($self) = @_;
  $self->app->log(debug => "removing broken streams");
  $self->streams([
    grep {!$_->disconnected} $self->streams
  ]);
}

sub handle_message {
  my ($self, $req) = @_;
  my $msg  = $req->param('msg');
  utf8::decode($msg);
  my $source = $req->param('source');
  my $window = $self->app->get_window($source);
  if ($window) {
    for (split /\n/, $msg) {
      eval {$self->app->dispatch($_, $window) if length $_};
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
  $req->respond([200, 'ok', {'Content-Type' => 'text/html; charset=utf-8'}, encode_utf8 $output]);
}

sub send_search {
  my ($self, $req) = @_;
  $self->app->history->search($req->vars, sub {
    my $rows = shift;
    my $content = $self->app->render('results', $rows);
    $req->respond([200, 'ok', {'Content-Type' => 'text/html; charset=utf-8'}, encode_utf8 $content]);
  });
}

sub send_range {
  my ($self, $req) = @_;
  my %query = $req->vars;
  $self->app->history->range($query{channel}, $query{time}, sub {
    my ($before, $after) = @_;
    $before = $self->app->render('range', $before, 'before');
    $after = $self->app->render('range', $after, 'after');
   $req->respond([200, 'ok', {'Content-Type' => 'text/html; charset=utf-8'}, to_json [$before, $after]]);
  });
}

sub send_config {
  my ($self, $req) = @_;
  $self->app->log(info => "serving config");
  my $output = $self->app->render('servers');
  $req->respond([200, 'ok', {}, $output]);
}

sub server_config {
  my ($self, $req) = @_;
  $self->app->log(info => "serving blank server config");
  my $name = $req->param('name');
  $name =~ s/\s+//g;
  my $config = $self->app->render('new_server', $name);
  my $listitem = $self->app->render('server_listitem', $name);
  $req->respond([200, 'ok', {"Cache-control" => "no-cache"}, 
                to_json({config => $config, listitem => $listitem})]);
}

sub save_config {
  my ($self, $req) = @_;
  $self->app->log(info => "saving config");
  my $new_config = {servers => {}};
  my %params = $req->vars;
  for my $name (keys %params) {
    next unless $params{$name};
    if ($name =~ /^(.+?)_(.+)/) {
      if ($2 eq "channels" or $2 eq "on_connect") {
        if (ref $params{$name} eq "ARRAY") {
          $new_config->{servers}{$1}{$2} = $params{$name};
        }
        else {
          $new_config->{servers}{$1}{$2} = [$params{$name}];
        }
      }
      else {
        $new_config->{servers}{$1}{$2} = $params{$name};
      }
    }
    else {
      $new_config->{$name} = $params{$name};
    }
  }
  $self->config->merge($new_config);
  $self->app->reload_config();
  $self->config->write;
  $req->respond([200, 'ok'])
}

sub tab_order  {
  my ($self, $req) = @_;
  $self->app->log(debug => "updating tab order");
  my %vars = $req->vars;
  $self->app->tab_order([
    grep {defined $_} @{$vars{tabs}}
  ]);
  $req->respond([200,'ok']);
}

sub not_found  {
  my ($self, $req) = @_;
  $self->app->log(debug => "sending 404 " . $req->path_info);
  my $res = $req->new_response(404);
  return $res->finalize;
}

__PACKAGE__->meta->make_immutable;
1;
