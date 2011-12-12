package Alice::InfoWindow;

use Encode;
use IRC::Formatting::HTML qw/irc_to_html/;
use Text::MicroTemplate qw/encoded_string/;

use parent 'Alice::Window';

sub new {
  my ($class, %args) = @_;

  for (qw/id render msg_iter/) {
    die "$_ is required" unless defined $args{$_};
  }
  
  $args{title} = "info";
  $args{topic} = {string => ""};
  $args{network} = "info";
  $args{type} = "info";
  $args{previous_nick} = "";

  bless \%args, __PACKAGE__;
}

sub is_channel {0}

sub hashtag {
  my $self = shift;
  return "/info";
}

sub format_message {
  my ($self, $from, $body, %options) = @_;

  my $html = irc_to_html($body, classes => 1, ($options{monospaced} ? () : (invert => "italic")));
  if ($options{multiline}) {
    $html = join "<br>", split "\n", $html;
  }

  my $message = {
    type   => "message",
    event  => "say",
    nick   => $from,
    window => $self->serialized,
    ($options{source} ? (source => $options{source}) : ()),
    html   => encoded_string($html),
    self   => $options{self} ? 1 : 0,
    hightlight  => $options{highlight} ? 1 : 0,
    msgid       => $msgid,
    timestamp   => time,
    monospaced  => $options{mono} ? 1 : 0,
    consecutive => $from eq $self->{previous_nick} ? 1 : 0,
  };

  $self->{previous_nick} = $from;

  $self->{msg_iter}->(sub {
    $message->{msgid} = shift;
    $message->{html} = $self->{render}->("message", $message);
    return $message;
  });
}

1;
