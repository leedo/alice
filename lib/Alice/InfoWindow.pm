package Alice::InfoWindow;

use Any::Moose;
use Encode;
use IRC::Formatting::HTML qw/irc_to_html/;
use Text::MicroTemplate qw/encoded_string/;

extends 'Alice::Window';

has '+title' => (required => 0, default => 'info');
has 'topic' => (is => 'ro', isa => 'HashRef', default => sub {{string => ''}});
has '+network' => (is => 'ro', default => "");
has '+type' => (is => 'ro', default => "info");

#
# DO NOT override the 'id' property, it is built in App/Alice.pm
# using the user-id, which is important for multiuser systems.
#

sub is_channel {0}

sub hashtag {
  my $self = shift;
  return "/info";
}

sub format_message {
  my ($self, $from, $body, %options) = @_;
  my $html = irc_to_html($body, classes => 1, ($options{monospaced} ? () : (invert => "italic")));

  my $message = {
    type   => "message",
    event  => "say",
    nick   => $from,
    window => $self->serialized,
    ($options{source} ? (source => $options{source}) : ()),
    html   => encoded_string($html),
    self   => $options{self} ? 1 : 0,
    hightlight  => $options{highlight} ? 1 : 0,
    msgid       => $self->buffer->next_msgid,
    timestamp   => time,
    monospaced  => $options{mono} ? 1 : 0,
    consecutive => $from eq $self->buffer->previous_nick ? 1 : 0,
  };

  $message->{html} = $self->render->("message", $message);

  $self->buffer->add($message);
  return $message;
}

__PACKAGE__->meta->make_immutable;
1;
