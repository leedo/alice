use 5.008001;
use MooseX::Declare;

=pod

=head1 NAME

App::Alice - the Altogether Lovely Internet Chat Experience

=cut

=head1 DESCRIPTION

Alice is an IRC client that can be run either locally or remotely, and
can be viewed in multiple web browsers at the same time. Alice stores
a message buffer, so when you load your browser you will get
the last 100 lines from each channel. This way you can close the 
web page and continue to collect messages to be read later.

Alice's built in web server maintains a long streaming HTTP response
to each connected browser. It uses this connection to push IRC messages
to the client in realtime. Sending messages and events to a channel
is done through a simple HTTP request back to the alice server.

=head1 NOTIFICATIONS

If you get a message with your nick in the body, and no browsers are
connected, a notification will be sent to either Growl (if running on
OS X) or using libnotify (on Linux.) Alice does not send any notifications
if a browser is connected (the exception being if you are using the Fluid
SSB which can access Growl). This is something that will probably become 
configurable over time.

=head1 RUNNING REMOTELY

Currently, there has been very little testing done for running alice
remotely. There is one bug that makes it potentially difficult,
and that only shows up if the server clock is significantly different
from that of the browser's OS. This can be fixed in the future by
calculating an offset and taking that into account.

=cut

class App::Alice {
  use App::Alice::Window;
  use App::Alice::HTTPD;
  use App::Alice::IRC;
  use MooseX::AttributeHelpers;
  use Digest::CRC qw/crc16/;
  use POE;

  our $VERSION = '0.01';

  has config => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
  );

  has ircs => (
    is      => 'ro',
    isa     => 'HashRef[HashRef]',
    default => sub {{}},
  );

  has httpd => (
    is      => 'ro',
    isa     => 'App::Alice::HTTPD',
    lazy    => 1,
    default => sub {
      App::Alice::HTTPD->new(app => shift);
    },
  );

  has dispatcher => (
    is      => 'ro',
    isa     => 'App::Alice::CommandDispatch',
    default => sub {
      App::Alice::CommandDispatch->new(app => shift);
    }
  );

  has notifier => (
    is      => 'ro',
    default => sub {
      eval {
        if ($^O eq 'darwin') {
          require App::Alice::Notifier::Growl;
          App::Alice::Notifier::Growl->new;
        }
        elsif ($^O eq 'linux') {
          require App::Alice::Notifier::LibNotify;
          App::Alice::Notifier::LibNotify->new;
        }
      }
    }
  );

  has window_map => (
    metaclass => 'Collection::Hash',
    isa       => 'HashRef[App::Alice::Window]',
    default   => sub {{}},
    provides  => {
      values => 'windows',
      set    => 'add_window',
      exists => 'has_window',
      get    => 'get_window',
      delete => 'remove_window',
      keys   => 'window_ids',
    }
  );
  
  method dispatch (Str $command, App::Alice::Window $window) {
    $self->dispatcher->handle($command, $window);
  }
  
  method nick_windows (Str $nick) {
    return grep {$_->includes_nick($nick)} $self->windows;
  }

  method buffered_messages (Int $min) {
    return [ grep {$_->{msgid} > $min} map {@{$_->msgbuffer}} $self->windows ];
  }

  method connections {
    return map {$_->connection} values %{$self->ircs};
  }

  method find_or_create_window (Str $title, $connection) {
    my $id = "win_" . crc16(lc($title . $connection->session_alias));
    if (my $window = $self->get_window($id)) {
      return $window;
    }
    my $window = App::Alice::Window->new(
      title      => $title,
      connection => $connection
    );  
    $self->add_window($id, $window);
  }

  method close_window (App::Alice::Window $window) {
    return unless $window;
    $self->send($window->close_action);
    $self->log_debug("sending a request to close a tab: " . $window->title)
      if $self->httpd->has_clients;
    $self->remove_window($window->id);
  }

  method add_irc_server (Str $name, HashRef $config) {
    $self->ircs->{$name} = App::Alice::IRC->new(
      app    => $self,
      alias  => $name,
      config => $config
    );
  }

  method run {
    $self->httpd;
    $self->add_irc_server($_, $self->config->{servers}{$_})
      for keys %{$self->config->{servers}};
    POE::Kernel->run;
  }

  sub send {
    my ($self, @messages) = @_;
    $self->httpd->send(@messages);
    return unless $self->notifier and ! $self->httpd->has_clients;
    for my $message (@messages) {
      $self->notifier->display($message) if $message->{highlight};
    }
  }

  sub log_debug {
    shift;
    print STDERR join(" ", @_) . "\n";
  }
}

=pod

=head1 AUTHORS

Lee Aylward E<lt>leedo@cpan.orgE<gt>

Sam Stephenson

Ryan Baumann

=head1 COPYRIGHT

Copyright 2009 by Lee Aylward E<lt>leedo@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
