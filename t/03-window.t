use Test::More;
use App::Alice;
use App::Alice::Test::NullHistory;
use Test::TCP;
use List::Util qw/shuffle/;

my $history = App::Alice::Test::NullHistory->new;
my $app = App::Alice->new(
  history => $history,
  standalone => 0,
  path => 't/alice',
  file => "test_config",
  port => empty_port(),
);

$app->add_irc_server("test", {
  nick => "tester",
  host => "not.real.server",
  port => 6667,
  autoconnect => 0,
});

my $irc = $app->get_irc("test");

{ 
  my $window = $app->create_window("test-window", $irc);
  ok $window->type eq "privmsg", "correct window type for privmsg";
  ok !$window->is_channel, "is_channel false for privmsg";
  $app->remove_window($window->id);
}

{
  $window = $app->create_window("#test-window", $irc);
  ok $window->type eq "channel", "correct window type for channel";
  ok $window->is_channel, "is_channel for channel";
  is $window->title, "#test-window", "window title";
  is $window->nick, "tester", "nick";
  is $window->topic->{string}, "no topic set", "default window topic";
  $app->remove_window($window->id);
}

{
  my @channels = qw/
    #TC.Premiere
    #alice
    #tc.beta
    #math-ag
    #math
    #not-math
    #TehConnection
    #topmath
    #hab
    #matematica
    #tc.torrentography
    #EvoBoxes
    ##cooking
  /;

  my @ids = map {$_->id} map {$app->create_window($_, $irc)} @channels;
  $app->tab_order(\@ids);

  is_deeply \@channels, $app->config->{order}, "tab order saved";
  is_deeply \@channels, [map {$_->title} $app->sorted_windows];
}

done_testing();
