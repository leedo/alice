package Plack::Middleware::WebSocket;
use strict;
use warnings;
use parent 'Plack::Middleware';

our $VERSION = '0.01';

sub call {
    my ($self, $env) = @_;

    $env->{'websocket.impl'} = Plack::Middleware::WebSocket::Impl->new($env);

    return $self->app->($env);
}

package Plack::Middleware::WebSocket::Impl;
use Plack::Util::Accessor qw(env error_code);
use Digest::MD5 qw(md5);
use Scalar::Util qw(weaken);
use IO::Handle;

sub new {
    my ($class, $env) = @_;
    my $self = bless { env => $env }, $class;
    weaken $self->{env};
    return $self;
}

sub handshake {
    my ($self, $respond) = @_;

    my $env = $self->env;

    unless ($env->{HTTP_CONNECTION} eq 'Upgrade' && $env->{HTTP_UPGRADE} eq 'WebSocket') {
        $self->error_code(400);
        return;
    }

    my $fh = $env->{'psgix.io'};
    unless ($fh) {
        $self->error_code(501);
        return;
    }

    my $key1 = $env->{'HTTP_SEC_WEBSOCKET_KEY1'};
    my $key2 = $env->{'HTTP_SEC_WEBSOCKET_KEY2'};
    my $n1 = join '', $key1 =~ /\d+/g;
    my $n2 = join '', $key2 =~ /\d+/g;
    my $s1 = $key1 =~ y/ / /;
    my $s2 = $key2 =~ y/ / /;
    $n1 = int($n1 / $s1);
    $n2 = int($n2 / $s2);

    my $len = read $fh, my $chunk, 8;
    unless (defined $len) {
        $self->error_code(500);
        return;
    }

    my $string = pack('N', $n1) . pack('N', $n2) . $chunk;
    my $digest = md5 $string;

    $fh->autoflush;

    print $fh join "\015\012", (
        'HTTP/1.1 101 Web Socket Protocol Handshake',
        'Upgrade: WebSocket',
        'Connection: Upgrade',
        "Sec-WebSocket-Origin: $env->{HTTP_ORIGIN}",
        "Sec-WebSocket-Location: ws://$env->{HTTP_HOST}$env->{SCRIPT_NAME}$env->{PATH_INFO}"
        . ($env->{QUERY_STRING} ? "?$env->{QUERY_STRING}" : ""),
        '',
        $digest,
    );

    return $fh;
}

package AnyEvent::Handle::Message::WebSocket;

sub anyevent_write_type {
    my ($handle, @args) = @_;
    return join '', "\x00", @args, "\xff";
}

sub anyevent_read_type {
    my ($handle, $cb) = @_;

    return sub {
        $_[0]{rbuf} =~ s/\x00(.*?)\xff// or return;
        $cb->($_[0], $1);
        1;
    };
}

1;

__END__

=head1 NAME

Plack::Middleware::WebSocket - Support WebSocket implementation

=head1 SYNOPSIS

  builder {
      enable 'WebSocket';
      sub {
          my $env = shift;
          ...
          if (my $fh = $env->{'websocket.impl'}->handshake) {
              # interact via $fh
              ...
          } else {
              $res->code($env->{'websocket.impl'}->error_code);
          }
      };
  };


=head1 DESCRIPTION

Plack::Middleware::WebSocket provides WebSocket implementation through $env->{'websocket.impl'}.
Currently implements draft-ietf-hybi-thewebsocketprotocol-00 <http://tools.ietf.org/html/draft-ietf-hybi-thewebsocketprotocol-00>.

=head1 METHODS

=over 4

=item my $fh = $env->{'websocket.impl'}->handshake;

Starts WebSocket handshake and returns filehandle on successful handshake.
If failed, $env->{'websocket.impl'}->error_code is set to an HTTP code.

=back

=head1 AUTHOR

motemen E<lt>motemen@gmail.comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
