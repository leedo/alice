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
has '+buffersize' => (default => 300);
has '+type' => (lazy => 0, default => 'info');

has '+irc' => (
  required => 0,
  lazy     => 1,
  default  => sub {
    my $self = shift;
    return ($self->app->connected_ircs)[0] if $self->app->connected_ircs == 1;
    $self->app->broadcast(
      $self->format_announcement("No server specified! /command -server args"));
    return undef;
  }
);

sub format_message {
  my ($self, $from, $body, $highlight, $monospaced) = @_;
  $highlight = 0 unless $highlight;
  my $html = IRC::Formatting::HTML->formatted_string_to_html($body);
  my $message = {
    type   => "message",
    event  => "say",
    nick   => $from,
    window => $self->serialized,
    inner_html => $monospaced ? "<span class=\"monospace\">$html</span>" : $html,
    self   => $highlight,
    msgid  => $self->app->next_msgid,
    monospaced => $monospaced ? 1 : 0,
  };
  $message->{outter_html} = $self->app->render("message", $message);
  $self->add_message($message);
  return $message;
}

__PACKAGE__->meta->make_immutable;
1;
