use MooseX::Declare;

class Alice::Notifier::Growl {
  use Mac::Growl ':all';

  sub BUILD {
    my $self = shift;
    RegisterNotifications("Alice", ["message"], ["message"], "Alice.app");
  }

  method display (HashRef $message) {
    PostNotification("Alice", "message", 
      $message->{nick} . " in " . $message->{window}->{title},
      $message->{body},
    );
  }
}
