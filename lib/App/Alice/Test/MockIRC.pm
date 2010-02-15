package App::Alice::Test::MockIRC;

use Any::Moose;
use AnyEvent::IRC::Util qw/parse_irc_msg prefix_nick mk_msg/;
use Try::Tiny;

has cbs => (is => 'rw', default => sub {{}});
has nick => (is => 'rw');
has user_prefix => (
  is => 'rw',
  lazy => 1,
  default => sub{$_[0]->nick."!".$_[0]->nick."\@host"}
);

has events => (
  is => 'rw',
  default => sub {
    my $self = shift;
    {
      TOPIC => sub {
        my $msg = shift;
        my $nick = prefix_nick($msg->{prefix});
        $self->cbs->{channel_topic}->($self, @{$msg->{params}}, $nick);
      },
      JOIN => sub {
        my $msg = shift;
        my $nick = prefix_nick($msg->{prefix});
        $self->cbs->{join}->($self, $nick, $msg->{params}[0], $nick eq $self->nick);
        $self->cbs->{channel_add}->($self, $msg, $msg->{params}[0], $nick)
      },
      PART => sub {
        my $msg = shift;
        my $nick = prefix_nick($msg->{prefix});
        $self->cbs->{part}->($self, $nick, $msg->{params}[0], $nick eq $self->nick);
        $self->cbs->{channel_remove}->($self, $msg, $msg->{params}[0], $nick);
      },
      numeric => sub {
        my ($msg, $number) = @_;
        $self->cbs->{"irc_$number"}->($self, $msg);
      },
    }
  }
);

sub send_srv {
  my ($self, $command, @args) = @_;
  
  my $echo = sub {mk_msg($self->user_prefix, $command, @args)};
  my $map = {
    map({$_ => $echo} qw/TOPIC JOIN PART/),
    WHO => sub{
      my $user = ($args[0] =~ /^#/ ? "test" : $args[0]);
      ":local.irc 352 ".$self->nick." #test $user il.comcast.net local.irc $user H :0 $user";
    },
  };
  $map->{$command} ? $self->simulate_line($map->{$command}->())
                   : warn "no line mapped for $command\n"
}

sub send_raw {
  my ($self, $line) = @_;
  $self->send_srv(split ' ', $line);
}

sub simulate_line {
  my ($self, $line) = @_;
  my $msg = parse_irc_msg($line);
  my $cmd = ($msg->{command} =~ /^\d+/ ? 'numeric' : $msg->{command});
  try { $self->events->{$cmd}->($msg, $msg->{command}); }
  catch { warn "$_\n" };
}

sub enable_ssl {}
sub ctcp_auto_reply {}
sub connect {
  my $self = shift;
  $self->cbs->{connect}->();
  $self->cbs->{registered}->();
}
sub disconnect {
  my $self = shift;
  $self->cbs->{disconnect}->();
}
sub enable_ping {}

sub reg_cb {
  my ($self, %callbacks) = @_;
  for (keys %callbacks) {
    $self->cbs->{$_} = $callbacks{$_}; 
  }
}

1;