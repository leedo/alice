use Test::More;
use Alice;
use Test::TCP;
use Alice::Test::MockIRC;

my $app = Alice->new(
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
$irc->cl(Alice::Test::MockIRC->new(nick => "tester"));
$app->connect_irc("test");
is_deeply [$app->ircs], [$irc], "connection list";

# windows
my $info = $app->info_window;
ok $info, "info window";
my $window = $app->create_window("test-window", $irc);
ok $window, "create window";

my $window_id = $app->_build_window_id("test-window", "test");
ok $app->has_window($window_id), "window exists";
ok $app->find_window("test-window", $irc), "find window by name";
ok ref $app->get_window($window_id) eq "Alice::Window", "get window";
is_deeply [$app->sorted_windows], [$info, $window], "window list";

is_deeply $app->find_or_create_window("test-window", $irc), $window, "find or create existing window";
my $window2 = $app->find_or_create_window("test-window2", $irc);
ok $app->find_window("test-window2", $irc), "find or create non-existent window";
$app->remove_window($app->_build_window_id("test-window2", "test"));

$app->close_window($window);
ok !$app->has_window($window_id), "close window";

# ignores
$app->add_ignore(msg => "jerk");
ok $app->is_ignore(msg => "jerk"), "add ignore";
$app->remove_ignore(msg => "jerk");
ok !$app->is_ignore("msg => jerk"), "remove ignore";

done_testing();
