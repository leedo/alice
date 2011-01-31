use Test::More;
use App::Alice;
use App::Alice::Test::NullHistory;
use Test::TCP;

my $history = App::Alice::Test::NullHistory->new;
my $app = App::Alice->new(
  history => $history,
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

# connections
ok $app->has_irc("test"), "add connection";
my $irc = $app->get_irc("test");
is_deeply [$app->ircs], [$irc], "connection list";

# windows
my $info = $app->info_window;
ok $info, "info window";
my $window = $app->create_window("test-window", $irc);
ok $window, "create window";

my $window_id = $app->_build_window_id("test-window", "test");
ok $app->has_window($window_id), "window exists";
ok $app->find_window("test-window", $irc), "find window by name";
ok ref $app->get_window($window_id) eq "App::Alice::Window", "get window";
is_deeply [$app->sorted_windows], [$info, $window], "window list";

is_deeply $app->find_or_create_window("test-window", $irc), $window, "find or create existing window";
my $window2 = $app->find_or_create_window("test-window2", $irc);
ok $app->find_window("test-window2", $irc), "find or create non-existent window";
$app->remove_window($app->_build_window_id("test-window2", "test"));

$app->close_window($window);
ok !$app->has_window($window_id), "close window";

# ignores
$app->add_ignore("jerk");
ok $app->is_ignore("jerk"), "add ignore";
is_deeply [$app->ignores], ["jerk"], "ignore list";
$app->remove_ignore("jerk");
ok !$app->is_ignore("jerk"), "remove ignore";
is_deeply [$app->ignores], [], "ignore list post remove";

done_testing();
