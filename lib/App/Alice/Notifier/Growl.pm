use MooseX::Declare;

class App::Alice::Notifier::Growl {
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
