package App::Alice::SleepMonitor;

use strict;
use warnings;
use POE qw/Wheel::Run Filter::Reference/;
use Mac::SleepEvent;
use feature ':5.10';

sub monitor {
  my $app = shift;
  POE::Session->create(
    inline_states => {
      _start  => \&async_spawn,
      stdout  => sub {
        my ($line, $wheel_id) = @_;
        print STDERR "Monitor stdout: $line\n";
        given ($line) {
          when ("sleep") {
            $_[HEAP]{app}->sleeping;
          }
          when ("wake") {
            $_[HEAP]{app}->waking;
          }
          when ("logout") {
            $_[HEAP]{app}->quitting;
          }
        }
      },
      debug => sub {
        print STDERR "Monitor debug: " . join(" ", @_) . "\n";
      },
    },
    heap => {
      app => $app
    }
  );
}

sub async_spawn {
  my $child = POE::Wheel::Run->new(
    Program => sub {
      my $monitor = Mac::SleepEvent->new(
        wake => sub {print "wake"},
        sleep => sub {print "sleep"},
        logout => sub {print "logout"},
      );
      $monitor->listen;
    },
    StdoutEvent => "debug",
    StderrEvent => "debug",
    CloseEvent  => "debug",
  );
}

1;