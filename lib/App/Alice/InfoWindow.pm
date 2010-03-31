package App::Alice::InfoWindow;

use Any::Moose;
use Encode;
use IRC::Formatting::HTML;
use Text::MicroTemplate qw/encoded_string/;

extends 'App::Alice::Window';

has '+is_channel' => (lazy => 0, default => 0);
has '+id' => (default => 'info');
has '+title' => (required => 0, default => 'info');
has '+session' => ( isa => 'Undef', default => undef);
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

sub format_message {
  my ($self, $from, $body, $highlight, $monospaced) = @_;
  $highlight = 0 unless $highlight;
  my $html = IRC::Formatting::HTML->formatted_string_to_html($body);
  my $message = {
    type   => "message",
    event  => "say",
    nick   => $from,
    window => $self->serialized,
    html   => encoded_string($html),
    self   => 0,
    hightlight => 0,
    msgid  => $self->app->next_msgid,
    timestamp => $self->timestamp,
    monospaced => $monospaced ? 1 : 0,
    consecutive => $from eq $self->messagelist->previous_nick ? 1 : 0,
  };
  $message->{html} = $self->app->render("message", $message);
  $self->messagelist->previous_nick($from);
  $self->messagelist->add($message);
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
    consecutive => $msg->{nick} eq $self->messagelist->previous_nick ? 1 : 0,
  };
  $self->messagelist->add($copy);
  return $copy;
}

__PACKAGE__->meta->make_immutable;
1;
