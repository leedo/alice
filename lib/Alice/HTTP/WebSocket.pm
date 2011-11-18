package Alice::HTTP::WebSocket;
use strict;
use warnings;
use parent 'Plack::Middleware';

our $VERSION = '0.01';
my $MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

sub call {
    my ($self, $env) = @_;

    $env->{'websocket.impl'} = Alice::HTTP::WebSocket::Impl->new($env);

    return $self->app->($env);
}

package Alice::HTTP::WebSocket::Impl;
use Plack::Util::Accessor qw(env error_code version);
use Scalar::Util qw(weaken);
use IO::Handle;
use Protocol::WebSocket::Handshake::Server;

sub new {
    my ($class, $env) = @_;
    my $self = bless { env => $env }, $class;
    weaken $self->{env};
    return $self;
}

sub handshake {
    my $self = shift;

    my $env = $self->env;

    my $hs = Protocol::WebSocket::Handshake::Server->new_from_psgi($env);

    my $fh = $env->{'psgix.io'};
    unless ($fh and $hs->parse($fh)) {
      $self->error_code(501);
      return;
    }

    if ($hs->is_done) {
      $fh->autoflush;
      print $fh $hs->to_string;
      $self->version($hs->version);
      return $fh;
    }

    $self->error_code(500);
}

package AnyEvent::Handle::Message::WebSocket;
use Protocol::WebSocket::Frame;

sub anyevent_write_type {
    my ($handle, @args) = @_;
    Protocol::WebSocket::Frame->new(
      version => $handle->{ws_version},
      buffer  => (join "", @args),
    )->to_bytes;
}

sub anyevent_read_type {
    my ($handle, $cb) = @_;

    $handle->{ws_frame} ||= Protocol::WebSocket::Frame->new(
      version => $handle->{ws_version}
    );

    return sub {
        my $frame = $_[0]->{ws_frame};
        $frame->append(delete $_[0]{rbuf});

        while (defined(my $message = $frame->next)) {
          if ($frame->is_close) {
            $_[0]->push_write(
              Protocol::WebSocket::Frame->new(
                type    => 'close',
                version => $_[0]->{ws_version},
              )
            );
            return;
          }
          elsif ($frame->is_ping) {
            $_[0]->push_write(
              Protocol::WebSocket::Frame->new(
                type    => 'ping',
                version => $_[0]->{ws_version},
              )
            );
            return;
          }

          $cb->($_[0], $message);
        }

        1;
    };
}

1;

__END__

=head1 NAME

Alice::HTTP::WebSocket - Support WebSocket implementation

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

Alice::HTTP::WebSocket provides WebSocket implementation through $env->{'websocket.impl'}.
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
