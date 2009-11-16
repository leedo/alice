package App::Alice::Notifier::Growl;

use Mac::Growl ':all';
use Moose;

sub BUILD {
  my $self = shift;
  RegisterNotifications("Alice", ["message"], ["message"], "Alice.app");
}

sub display {
  my ($self, $message) = @_;
  PostNotification("Alice", "message", 
    $message->{nick} . " in " . $message->{window}->{title},
    $message->{body},
  );
}

__PACKAGE__->meta->make_immutable;
1;