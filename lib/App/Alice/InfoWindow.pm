package App::Alice::InfoWindow;

use Any::Moose;
use Encode;
use IRC::Formatting::HTML qw/irc_to_html/;
use Text::MicroTemplate qw/encoded_string/;

extends 'App::Alice::Window';

has '+is_channel' => (lazy => 0, default => 0);
has '+title' => (required => 0, default => 'info');
has '+session' => (default => "");
has 'topic' => (is => 'ro', isa => 'HashRef', default => sub {{string => ''}});
has '+type' => (lazy => 0, default => 'info');
has '+_irc' => (required => 0, isa => 'Any');

sub irc {
  my $self = shift;
  return ($self->app->connected_ircs)[0] if $self->app->connected_ircs == 1;
  $self->app->broadcast(
    $self->format_announcement("No server specified! /command -server args"));
  return undef;
}

sub all_nicks {
  return [];
}

sub format_message {
  my ($self, $from, $body, %options) = @_;
  my $html = irc_to_html($body);
  my $message = {
    type   => "message",
    event  => "say",
    nick   => $from,
    window => $self->serialized,
    html   => encoded_string($html),
    self   => $options{self} ? 1 : 0,
    hightlight => $options{highlight} ? 1 : 0,
    msgid  => $self->app->next_msgid,
    timestamp => time,
    monospaced => $options{mono} ? 1 : 0,
    consecutive => $from eq $self->buffer->previous_nick ? 1 : 0,
  };
  $message->{html} = $self->app->render("message", $message);
  $self->buffer->add($message);
  return $message;
}

sub copy_message {
  my ($self, $msg) = @_;
  my $copy = {
    type   => "message",
    event  => "say",
    nick   => $msg->{nick},
    window => $self->serialized,
    html   => $msg->{html},
    self   => $msg->{self},
    highlight => $msg->{highlight},
    msgid  => $self->app->next_msgid,
    timestamp => $msg->{timestamp},
    monospaced => $msg->{monospaced},
    consecutive => $msg->{nick} eq $self->buffer->previous_nick ? 1 : 0,
  };
  if ($msg->{consecutive} and !$copy->{consecutive}) {
    $copy->{html} =~ s/(<li class="[^"]*)consecutive/$1/;
  } elsif (!$msg->{consecutive} and $copy->{consecutive}) {
    $copy->{html} =~ s/(<li class=")/$1consecutive /;
  }
  $self->buffer->add($copy);
  return $copy;
}

__PACKAGE__->meta->make_immutable;
1;
