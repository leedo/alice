package App::Alice::Notifier::LibNotify;

use Desktop::Notify;
use Moose;

has 'client' => (
  is      => 'ro',
  isa     => 'Desktop::Notify',
  default => sub {
    return Desktop::Notify->new;
  }
);

sub display {
  my ($self, $message) = @_;
  my $notification = $self->client->create(
    summary => $message->{nick} . " in " . $message->{window}->{title},
    body    => $message->{body},
    timeout => 3000);
  $notification->show;
}

__PACKAGE__->meta->make_immutable;
1;