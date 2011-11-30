package Alice::IRC;

use AnyEvent;
use AnyEvent::IRC::Client;
use AnyEvent::IRC::Util qw/parse_irc_msg/;
use List::MoreUtils qw/any/;
use Digest::MD5 qw/md5_hex/;
use Any::Moose;
use Encode;

my $email_re = qr/([^<\s]+@[^\s>]+\.[^\s>]+)/;
my $image_re = qr/(https?:\/\/\S+(?:jpe?g|png|gif))/i;

{
  no warnings;

  # YUCK!!!
  *AnyEvent::IRC::Connection::_feed_irc_data = sub {
    my ($self, $line) = @_;
    my $m = parse_irc_msg (decode ("utf8", $line));
    $self->event (read => $m);
    $self->event ('irc_*' => $m);
    $self->event ('irc_' . (lc $m->{command}), $m);
  };

  *AnyEvent::IRC::Connection::mk_msg = \&mk_msg;
  *AnyEvent::IRC::Client::mk_msg = \&mk_msg;
}

has 'cl' => (is => 'rw');

has 'name' => (
  is       => 'ro',
  required => 1,
);

has 'reconnect_timer' => (
  is => 'rw'
);

has [qw/is_connecting reconnect_count connect_time/] => (
  is  => 'rw',
  default   => 0,
);

sub increase_reconnect_count {$_[0]->reconnect_count($_[0]->reconnect_count + 1)}
sub reset_reconnect_count {$_[0]->reconnect_count(0)}

has [qw/disabled removed/] => (
  is  => 'rw',
  default => 0,
);

has whois => (
  is        => 'rw',
  default   => sub {{}},
);

has avatars => (
  is        => 'rw',
  default   => sub {{}},
);

sub add_whois {
  my ($self, $nick, $cb) = @_;
  $nick = lc $nick;
  $self->whois->{$nick} = {info => "", cb => $cb};
  $self->send_srv(WHOIS => $nick);
}

sub new_client {
  my ($self, $events, $config) = @_;

  my $client = AnyEvent::IRC::Client->new(send_initial_whois => 1);
  $client->enable_ssl if $config->{ssl};
  $client->reg_cb(%$events);
  $client->ctcp_auto_reply ('VERSION', ['VERSION', "alice $Alice::VERSION"]);

  $self->cl($client);
}

sub send_srv {
  my $self = shift;
  $self->cl->send_srv(@_) if $self->cl;
}

sub send_long_line {
  my ($self, $cmd, @params) = @_;
  my $msg = pop @params;
  my $ident = $self->cl->nick_ident($self->cl->nick);
  my $init_len = length mk_msg($ident, $cmd, @params, " ");

  my $max_len = 500; # give 10 bytes extra margin
  my $line_len = $max_len - $init_len;

  # split up the multiple lines in the message:
  my @lines = split /\n/, $msg;
  @lines = map split_unicode_string ("utf-8", $_, $line_len), @lines;

  $self->cl->send_srv($cmd => @params, $_) for @lines;
}

sub send_raw {
  my $self = shift;
  $self->cl->send_raw(encode "utf8", $_[0]);
}

sub is_connected {
  my $self = shift;
  $self->cl ? $self->cl->is_connected : 0;
}

sub is_disconnected {
  my $self = shift;
  return !($self->is_connected or $self->is_connecting);
}

sub nick {
  my $self = shift;
  my $nick = $self->cl->nick;
}

sub nick_avatar {
  my $self = shift;
  return $self->avatars->{$_[0]} || "";
}

sub channels {
  my $self = shift;
  return keys %{$self->cl->channel_list};
}

sub channel_nicks {
  my ($self, $channel, $mode) = @_;
  my $nicks = $self->cl->channel_list($channel);
  return map {
    $mode ? $self->prefix_from_modes($_, $nicks->{$_}).$_ : $_;
  } keys %$nicks;
}

sub prefix_from_modes {
  my ($self, $nick, $modes) = @_;
  for my $mode (keys %$modes) {
    if (my $prefix = $self->cl->map_mode_to_prefix($mode)) {
      return $prefix;
    }
  }
  return "";
}

sub nick_channels {
  my ($self, $nick) = @_;
  grep {any {$nick eq $_} $self->channel_nicks($_)} $self->channels;
}

sub realname_avatar {
  my ($self, $realname) = @_;

  if ($realname =~ $email_re) {
    my $email = $1;
    return "http://www.gravatar.com/avatar/"
           . md5_hex($email) . "?s=32&amp;r=x";
  }
  elsif ($realname =~ $image_re) {
    return $1;
  }

  return ();
}

sub update_realname {
  my ($self, $realname) = @_;
  $self->send_srv(REALNAME => $realname);
  $self->avatars->{$self->nick} = $self->realname_avatar($realname);
}

sub is_channel {
  my ($self, $channel) = @_;
  return $self->cl->is_channel_name($channel);
}

sub split_unicode_string {
  my ($enc, $str, $maxlen) = @_;

  return $str unless length (encode ($enc, $str)) > $maxlen;

  my $cur_out = '';
  my $word = '';
  my @lines;

  while (length ($str) > 0) {
    $word .= substr $str, 0, 1, '';

    if ($word =~ /\w\W$/
        || length ($str) == 0
        || length ( encode ($enc, $word)) >= $maxlen) {

      if (length (encode ($enc, $cur_out.$word)) > $maxlen) {
        push @lines, $cur_out;
        $cur_out = '';
      }

      $cur_out .= $word;
      $word = '';
    }
  }

  push @lines, $cur_out if length ($cur_out);
  return @lines;
}

sub mk_msg {
  encode "utf8", AnyEvent::IRC::Util::mk_msg(@_);
}

__PACKAGE__->meta->make_immutable;
1;
