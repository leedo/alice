use MooseX::Declare;

class App::Alice::InfoWindow extends App::Alice::Window {
  has '+is_channel' => ( default => 0 );
  has '+id' => ( default => 'info' );
  has '+title' => (required => 0, default => 'info');
  has '+connection' => ( required => 0 );
  has '+session' => ( isa => 'Undef', default => undef );
  has 'topic' => (is => 'ro', isa => 'HashRef', default => sub {{Value => 'info'}});
  has '+buffersize' => ( default => 300 );
  
  method render_message (Str $from, Str $body, Bool :$highlight = 0) {
    my $message = {
      type   => "message",
      event  => "say",
      nick   => $from,
      window => $self->serialized,
      body   => $body,
      self   => $highlight,
      html   => $body,
      msgid  => $self->next_msgid,
    };
    my $full_html = '';
    $self->tt->process("message.tt", $message, \$full_html);
    $message->{full_html} = $full_html;
    $self->add_message($message);
    return $message;
  }
}