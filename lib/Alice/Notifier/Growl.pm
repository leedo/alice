use MooseX::Declare;

class {
  use Growl::GNTP;

  has 'connection' => (
    is => 'ro',
    isa => 'Growl::GNTP',
    default => sub {
      return Growl::GNTP->new(AppName => 'Alice');
    }
  );

  method BUILD {
    $self->connection->register([{ Name => "message" }]);
  }

  method display (HashRef $message) {
    $self->notify(
      Event => "message",
      Title => $message->{nick} . " in " . $message->{window}->{title},
      Message => $message->{message},
    );
  }
}
