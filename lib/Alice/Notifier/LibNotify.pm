use MooseX::Declare;

class Alice::Notifier::LibNotify {
  use Desktop::Notify;

  has 'connection' => (
    is      => 'ro',
    isa     => 'Desktop::Notify',
    default => sub {
      return Desktop::Notify->new;
    }
  );

  method display (HashRef $message) {
    my $notification = $self->connection->create(
      summary => $message->{nick} . " in " . $message->{window}->{title},
      body    => $message->{body},
      timeout => 3000);
    $notification->show;
  }
}
