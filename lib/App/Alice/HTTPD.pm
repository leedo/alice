package App::Alice::HTTPD;

use AnyEvent;
use AnyEvent::HTTPD;
use AnyEvent::HTTP;
use Moose;
use App::Alice::CommandDispatch;
use MIME::Base64;
use Time::HiRes qw/time/;
use JSON;
use Template;

has 'app' => (
  is  => 'ro',
  isa => 'App::Alice',
  required => 1,
);

has 'condvar' => (
  is  => 'rw',
  isa => 'AnyEvent::CondVar',
);

has 'httpd' => (
  is  => 'rw',
  isa => 'AnyEvent::HTTPD'
);

has 'streams' => (
  is  => 'rw',
  isa => 'ArrayRef',
  default => sub {[]},
);

has 'seperator' => (
  is  => 'ro',
  isa => 'Str',
  default => 'xalicex',
);

has 'tt' => (
  is => 'ro',
  isa => 'Template',
  lazy => 1,
  default => sub { shift->app->tt }
);

has 'config' => (
  is => 'ro',
  isa => 'App::Alice::Config',
  lazy => 1,
  default => sub {shift->app->config},
);

sub BUILD {
  my $self = shift;
  $self->meta->error_class('Moose::Error::Croak');
  $self->condvar(AnyEvent->condvar);
  my $httpd = AnyEvent::HTTPD->new(
    port => $self->config->port,
  );
  $httpd->reg_cb(
    '/serverconfig' => sub{$self->server_config(@_)},
    '/config'       => sub{$self->send_config(@_)},
    '/save'         => sub{$self->save_config(@_)},
    '/tabs'         => sub{$self->tab_order(@_)},
    '/view'         => sub{$self->send_index(@_)},
    '/stream'       => sub{$self->setup_stream(@_)},
    '/favicon.ico'  => sub{$self->not_found($_[1])},
    '/say'          => sub{$self->handle_message(@_)},
    '/static'       => sub{$self->handle_static(@_)},
    '/get'          => sub{$self->image_proxy(@_)},
    'client_disconnected' => sub{$self->purge_disconnects(@_)},
  );
  $self->httpd($httpd);
  $self->ping;
}

sub ping {
  my $self = shift;
  AnyEvent->timer(
    after    => 0,
    interval => 10,
    cb       => sub {
      $self->broadcast({
        type => "action",
        event => "ping",
      })
    }
  );
}

sub image_proxy {
  my ($self, $httpd, $req) = @_;
  my $url = $req->url;
  $url =~ s/^\/get\///;
  http_get $url, sub {
    my ($data, $headers) = @_;
    $req->respond([$headers->{Status},$headers->{Reason},$headers,$data]);
  };
}

sub broadcast {
  my ($self, $data, $force) = @_;
  return unless $self->has_clients;
  
  for my $res (@{$self->streams}) {
    for my $item (@$data) {
      if ($item->{type} eq "message") {
        push @{$res->{msgs}}, $item
      }
      elsif ($item->{type} eq "action") {
        push @{$res->{actions}}, $item
      }
    }
  }
  $self->send_stream($_) for @{$self->streams};
};

sub check_authentication {
  my ($self, $httpd, $req) = @_;
  unless ($self->config->auth
      and ref $self->config->auth eq 'HASH'
      and $self->config->auth->{username}
      and $self->config->auth->{password}) {
    $req->respond([200,'ok']) 
  }

  if (my $auth  = $req->headers->{authorization}) {
    $auth =~ s/^Basic //;
    $auth = decode_base64($auth);
    my ($user,$password)  = split(/:/, $auth);
    if ($self->config->auth->{username} eq $user &&
        $self->config->auth->{password} eq $password) {
      $req->respond([200,'ok']);
      return;
    }
    else {
      $self->log_debug("auth failed");
    }
  }
  $req->respond([401, 'unauthorized', {'WWW-Authenticate' => 'Basic realm="Alice"'}]);
}

sub setup_stream {
  my ($self, $httpd, $req) = @_;
  
  my $local_time = time;
  my $remote_time = $req->parm('t') || $local_time;
  
  # TODO make a real stream class for this
  my $stream = {
    msgs      => [],
    actions   => [ map {$_->nicks_action} $self->app->windows ],
    offset    => $local_time - $remote_time,
    last_send => 0,
    delayed   => 0,
    data_cb   => sub {print STDERR "no data cb setup yet\n"},
  };
  
  my $res = $req->respond([
    200, 'ok', 'multipart/mixed; boundary='.$self->seperator.'; charset=utf-8',
    sub {$stream->{data_cb} = shift} ]);
  
  $stream->{res} = $res;
  
  $self->log_debug("opening new stream");

  # populate the msg queue with any buffered messages
  if (defined (my $msgid = $req->parm('msgid'))) {
    $stream->{msgs} = $self->app->buffered_messages($msgid);
  }
  push @{$self->streams}, $stream;
  $self->send_stream($stream);
}

sub send_stream {
  my ($self, $stream) = @_;
  my $diff = time - $stream->{last_send};
  if ($diff < 0.1 and !$stream->{resend_id}) {
    $stream->{delayed} = 1;
    $stream->{resend_id} = AnyEvent->timer(
      after => 0.1 - $diff,
      cb    => sub {$self->send_stream($stream)}
    );
    return;
  }
  if (@{$stream->{msgs}} or @{$stream->{actions}}) {
    use bytes;
    my $output;
    if (! $stream->{started}) {
      $stream->{started} = 1;
      $output .= '--'.$self->seperator."\n";
    }
    $output .= to_json({msgs => $stream->{msgs}, actions => $stream->{actions},
                        time => time - $stream->{offset}});
    $output .= " " x (1024 - bytes::length $output) if bytes::length $output < 1024;
    $stream->{data_cb}->("$output\n--" . $self->seperator . "\n");
  
    $stream->{msgs} = [];
    $stream->{actions} = [];
    $stream->{last_send} = time;
    no bytes;
  }
  $stream->{resend_id} = undef;
}

sub purge_disconnects {
  my ($self, $host, $port) = @_;
  for (0 .. scalar @{$self->streams} - 1) {
    my $stream = $self->streams->[$_];
    if (!$stream->{data_cb}) {
      splice @{$self->streams}, $_, 1;
    }
  }
}

sub handle_message {
  my ($self, $httpd, $req) = @_;
  my $msg  = $req->parm('msg');
  my $source = $req->parm('source');
  my $window = $self->app->get_window($source);
  if ($window) {
    for (split /\n/, $msg) {
      eval {$self->app->dispatch($_, $window) if length $_};
      if ($@) {$self->log_debug($@)}
    }
  }
  $req->respond([200,'ok',{'Content-Type' => 'text/plain'}, 'ok']);
}

sub handle_static {
  my ($self, $httpd, $req) = @_;
  my $file = $req->url;
  my ($ext) = ($file =~ /[^\.]\.(.+)$/);
  my $headers;
  if (-e $self->config->assetdir . "/$file") {
    open my $fh, '<', $self->config->assetdir . "/$file";
    if ($ext =~ /^(?:png|gif|jpg|jpeg)$/i) {
      $headers = {"Content-Type" => "image/$ext"};
    }
    elsif ($ext =~ /^js$/) {
      $headers = {
        "Cache-control" => "no-cache",
        "Content-Type" => "text/javascript",
      };
    }
    elsif ($ext =~ /^css$/) {
      $headers = {
        "Cache-control" => "no-cache",
        "Content-Type" => "text/css",
      };
    }
    else {
      return $self->not_found($req);
    }
    my @file = <$fh>;
    $req->respond([200, 'ok', $headers, join("", @file)]);
    return;
  }
  $self->not_found($req);
}

sub send_index {
  my ($self, $httpd, $req) = @_;
  my $output = '';
  my $channels = [];
  for my $window ($self->sorted_windows) {
    push @$channels, {
      window  => $window->serialized(encoded => 1),
      topic   => $window->topic,
    }
  }
  $self->tt->process('index.tt', {
    windows => $channels,
    style   => $self->config->style  || "default",
    images  => $self->config->images,
    monospace_nicks => $self->config->monospace_nicks,
  }, \$output) or die $!;
  $req->respond([200, 'ok', {'Content-Type' => 'text/html; charset=utf-8'}, $output]);
}

sub sorted_windows {
  my $self = shift;
  my %order;
  if ($self->config->order) {
    %order = map {$self->config->order->[$_] => $_}
             0 .. @{$self->config->order} - 1;
  }
  $order{info} = "##";
  sort {
    my ($c, $d) = ($a->title, $b->title);
    $c =~ s/^#//;
    $d =~ s/^#//;
    $c = $order{$a->title} . $c if exists $order{$a->title};
    $d = $order{$b->title} . $d if exists $order{$b->title};
    $c cmp $d;
  } $self->app->windows
}

sub send_config {
  my ($self, $httpd, $req) = @_;
  $self->log_debug("serving config");
  my $output = '';
  $self->tt->process('config.tt', {
    style       => $self->config->style || "default",
    config      => $self->config->serialized,
    connections => [ sort {$a->alias cmp $b->alias}
                     $self->app->connections ],
  }, \$output);
}

sub server_config {
  my ($self, $httpd, $req) = @_;
  $self->log_debug("serving blank server config");
  my $name = $req->parm('name');
  my $config = '';
  $self->tt->process('server_config.tt', {name => $name}, \$config);
  my $listitem = '';
  $self->tt->process('server_listitem.tt', {name => $name}, \$listitem);
  $req->respond([200, 'ok', {"Cache-control" => "no-cache"}, 
                to_json({config => $config, listitem => $listitem})]);
}

sub save_config {
  my ($self, $httpd, $req) = @_;
  $self->log_debug("saving config");
  my $new_config = {};
  for my $name ($req->params) {
    next unless $req->parm($name);
    if ($name =~ /^(.+?)_(.+)/) {
      if ($2 eq "channels" or $2 eq "on_connect") {
        $new_config->{servers}{$1}{$2} = [$req->parm($name)];
      }
      else {
        $new_config->{servers}{$1}{$2} = $req->parm($name);
      }
    }
    else {
      $new_config->{$name} = $req->parm($name);
    }
  }
  $self->config->merge($new_config);
  $self->config->write;
  $req->respond->([200, 'ok'])
}

sub tab_order  {
  my ($self, $httpd, $req) = @_;
  $self->log_debug("updating tab order");
  my %vars = $req->vars;
  $self->app->tab_order([
    grep {defined $_} @{$vars{tabs}}
  ]);
  $req->respond([200,'ok']);
}

sub not_found  {
  my ($self, $req) = @_;
  $self->log_debug("404: ", $req->url);
  $req->respond([404,'not found']);
}

sub has_clients {
  my $self = shift;
  return scalar @{$self->streams} > 0;
}

sub log_debug {
  my $self = shift;
  print STDERR join " ", @_ if $self->config->debug;
  print "\n";
}

sub log_info {
  print STDERR join " ", @_;
  print STDERR "\n";
}

__PACKAGE__->meta->make_immutable;
1;
