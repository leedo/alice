package App::Alice::Stream::WebSocket;

use JSON;
use Any::Moose;
use Digest::MD5 qw/md5/;

has env => (
  is => 'ro',
  required => 1,
);

has handle => (
  is => 'rw',
);

has [qw/offset last_send start_time/]=> (
  is  => 'rw',
  isa => 'Num',
  default => 0,
);

has closed => (
  is => 'rw',
  default => 0,
);

has on_read => (
  is => 'ro',
  isa => 'CodeRef',
);

sub BUILD {
  my $self = shift;

  my $local_time = time;
  my $remote_time = $self->start_time || $local_time;
  $self->offset($local_time - $remote_time);

  my $env = $self->env;

  my $hh = join "\015\012", (
    'HTTP/1.1 101 Web Socket Protocol Handshake',
    'Upgrade: WebSocket',
    'Connection: Upgrade',
    "Sec-WebSocket-Origin: $env->{HTTP_ORIGIN}",
    "Sec-WebSocket-Location: ws://$env->{HTTP_HOST}$env->{SCRIPT_NAME}$env->{PATH_INFO}",
    '',
  );

  my $fh = $env->{'psgix.io'};

  my $key1 = $env->{'HTTP_SEC_WEBSOCKET_KEY1'};
  my $key2 = $env->{'HTTP_SEC_WEBSOCKET_KEY2'};
  my $n1 = join '', $key1 =~ /\d+/g;
  my $n2 = join '', $key2 =~ /\d+/g;
  my $s1 = $key1 =~ y/ / /;
  my $s2 = $key2 =~ y/ / /;
  $n1 = int($n1 / $s1);
  $n2 = int($n2 / $s2);

  my $len = read $fh, my $chunk, 8;
  die "read: $!" unless defined $len;

  my $string = pack('N', $n1) . pack('N', $n2) . $chunk;
  my $digest = md5 $string;
  
  my $h = AnyEvent::Handle->new(fh => $fh);
  $h->push_write($hh);
  $h->push_write("\015\012");
  $h->push_write("$digest");
  
  $h->on_error(sub {
    warn $_[2];
    $self->close;
    undef $h;
  });

  $h->on_eof(sub {
    warn $_[2];
    $self->close;
    undef $h;
  }); 

  $h->on_read(sub {
    $_[0]->push_read(
      line => "\xff",
      sub {
        my ($h, $line) = @_;
        $line =~ s/^\0// or warn;
        $self->on_read->($self, decode_json $line);
      }
    );
  });
    
  $self->handle($h);
}

sub send {
  my ($self, $messages) = @_;

  my $line = to_json({
    queue => $messages,
    time  => time - $self->offset,
  }, {utf8 => 1, shrink => 1});
  
  $self->handle->push_write("\x00$line\xff");
}

sub close {
  my $self = shift;
  $self->handle->destroy;
  $self->handle(undef);
  $self->closed(1);
}

__PACKAGE__->meta->make_immutable;
1;
