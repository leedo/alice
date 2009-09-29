use MooseX::Declare;

class App::Alice::Notifier::LibNotify {
  use Desktop::Notify;

  has 'client' => (
    is      => 'ro',
    isa     => 'Desktop::Notify',
    default => sub {
      return Desktop::Notify->new;
    }
  );

  method display (HashRef $message) {
    my $notification = $self->client->create(
      summary => $message->{nick} . " in " . $message->{window}->{title},
      body    => $message->{body},
      timeout => 3000);
    $notification->show;
  }
}
