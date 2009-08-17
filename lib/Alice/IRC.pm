use MooseX::Declare;

class Alice::IRC {
  use MooseX::POE::SweetArgs qw/event/;
  use POE::Component::IRC;
  use POE::Component::IRC::State;
  use POE::Component::IRC::Plugin::Connector;
  use POE::Component::IRC::Plugin::CTCP;
  use POE::Component::IRC::Plugin::NickReclaim;

  has 'connection' => (
    is      => 'rw',
    default => sub {{}},
  );

  has 'alias' => (
    isa      => 'Str',
    is       => 'ro',
    required => 1,
  );
  
  has 'config' => (
    isa      => 'HashRef',
    is       => 'rw',
    required => 1,
  );

  has 'app' => (
    isa      => 'Alice',
    is       => 'ro',
    required => 1,
  );

  sub START {
    my $self = shift;
    if ($self->config->{ssl}) {
      eval { require POE::Component::SSLify };
      die "Missing module POE::Component::SSLify" if ($@);
    }
    my $irc = POE::Component::IRC::State->spawn(
      alias    => $self->alias,
      nick     => $self->config->{nick},
      ircname  => $self->config->{ircname},
      server   => $self->config->{host},
      port     => $self->config->{port},
      password => $self->config->{password},
      username => $self->config->{username},
      UseSSL   => $self->config->{ssl},
      msg_length => 1024,
    );
    $self->connection($irc);
    $self->add_plugins;
    $self->connection->yield(register => 'all');
    
    $self->log_info("connecting to " . $self->alias);
    $self->connection->yield(connect => {});
  }
  
  method add_plugins {
    my $irc = $self->connection;
    $irc->{connector} = POE::Component::IRC::Plugin::Connector->new(
      delay => 20, reconnect => 10);
    $irc->plugin_add('Connector' => $irc->{connector});
    $irc->plugin_add('CTCP' => POE::Component::IRC::Plugin::CTCP->new(
      version => 'alice',
      userinfo => $irc->nick_name
    ));
    $irc->plugin_add('NickReclaim' => POE::Component::IRC::Plugin::NickReclaim->new());
  }

  method window (Str $title){
    my $window = $self->app->window($self->alias, $title);
    if (! $window) {
      $window = $self->app->create_window($title, $self->connection);
    }
    return $window;
  }

  event irc_001 => sub {
    my $self = shift;
    $self->log_info("connected to " . $self->alias);
    for (@{$self->config->{on_connect}}) {
      $self->log_debug("sending $_");
      $self->connection->yield( quote => $_ );
    }
    for (@{$self->config->{channels}}) {
      $self->log_debug("joining $_");
      $self->connection->yield( join => $_ );
    }
  };
  
  event irc_353 => sub {
    my ($self, $server, $msg, $msglist) = @_;
    my $channel = $msglist->[1];
    my $window = $self->window($channel);
    return unless $window;
    my @nicks = map {s/^[@&]//} split " ", $msglist->[2];
    my $topic = $window->topic;
    my $message = $window->render_event("topic", $topic->{SetBy} || "", $topic->{Value} || "");
    $message->{nicks} = [@nicks];
    $self->app->send($message);
  };

  event irc_disconnected => sub {
    my $self = shift;
    $self->log_info("disconnected from " . $self->alias);
  };

  event irc_public => sub {
    my ($self, $who, $where, $what) = @_;
    my $nick = ( split /!/, $who )[0];
    my $window = $self->window($where->[0]);
    $self->app->send($window->render_message($nick, $what));
  };

  event irc_msg => sub {
    my ($self, $who, $recp, $what) = @_;
    my $nick = ( split /!/, $who)[0];
    my $window = $self->window($nick);
    $self->app->send($window->render_message($nick, $what));
  };

  event irc_ctcp_action => sub {
    my ($self, $who, $where, $what) = @_;
    my $nick = ( split /!/, $who )[0];
    my $window = $self->window($where->[0]);
    $self->app->send($window->render_message($nick, "• $what"));
  };

  event irc_nick => sub {
    my ($self, $who, $new_nick) = @_;
    my $nick = ( split /!/, $who )[0];
    my @events = map {
      $self->window($_)->render_event("nick", $nick, $new_nick)
    } $self->connection->nick_channels($new_nick);
    $self->app->send(@events)
  };

  event irc_join => sub {
    my ($self, $who, $where) = @_;
    my $nick = ( split /!/, $who)[0];
    if ($nick ne $self->connection->nick_name) {
      my $window = $self->window($where);
      $self->app->send($window->render_event("joined", $nick));
    }
    else {
      # this should be happening at irc_366 now
      # $self->app->create_window($where, $self->connection);
    }
  };

  event irc_part => sub {
    my ($self, $who, $where, $msg) = @_;
    my $nick = ( split /!/, $who)[0];
    my $window = $self->window($where);
    return unless $window;
    if ($nick ne $self->connection->nick_name) {
      $self->app->send($window->render_event("left", $nick, $msg));
    }
    else {
      $self->app->close_window($window);
    }
  };

  event irc_quit => sub {
    my ($self, $who, $msg, $channels) = @_;
    my $nick = ( split /!/, $who)[0];
    my @events = map {
      my $window = $self->window($_);
      $window->render_event("left", $nick, $msg);
    } @$channels;
    $self->app->send(@events);
  };

  event irc_topic => sub {
    my ($self, $who, $channel, $topic) = @_;
    my $nick = (split /!/, $who)[0];
    my $window = $self->window($channel);
    $self->app->send($window->render_event("topic", $nick, $topic));
  };

  sub log_debug {
    my $self = shift;
    print STDERR join " ", @_, "\n" if $self->app->config->{debug};
  }

  sub log_info {
    my $self = shift;
    print STDERR join " ", @_, "\n";
  }
}