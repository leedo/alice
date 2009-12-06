package App::Alice::Notifier::Growl;

use Any::Moose;

sub BUILD {
  my $self = shift;
  require Mac::Growl;
  Mac::Growl->import(":all");
  RegisterNotifications("Alice", ["message"], ["message"]);
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
