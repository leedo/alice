use Test::More;
use App::Alice;

my $app = App::Alice->new(
  standalone => 0, path => 't', file => "test_config");

$app->add_irc_server("test", {
  nick => "tester",
  host => "not.real.server",
  port => 6667,
  autoconnect => 0,
});

# connections
ok $app->ircs->{test}, "add connection";
my $irc = $app->ircs->{test};
is_deeply [$app->connections], [$irc], "connection list";

# windows
my $info = $app->info_window;
ok $info, "info window";
my $window = $app->create_window("test-window", $irc);
ok $window, "create window";

my $window_id = App::Alice::_build_window_id("test-window", "test");
is $window_id, "win_testwindowtest", "build window id";
ok $app->has_window($window_id), "window exists";
ok $app->find_window("test-window", $irc), "find window by name";
ok ref $app->get_window($window_id) eq "App::Alice::Window", "get window";
is_deeply [$app->window_ids], ["info", $window_id], "window id list";
is_deeply [$app->windows], [$info, $window], "window list";

$app->add_window("test-window2", {});
ok $app->has_window("test-window2"), "manually add window";
$app->remove_window("test-window2");
ok !$app->has_window("test-window2"), "manually remove window";

is_deeply $app->find_or_create_window("test-window", $irc), $window, "find or create existing window";
my $window2 = $app->find_or_create_window("test-window2", $irc);
ok $app->find_window("test-window2", $irc), "find or create non-existent window";
$app->remove_window(App::Alice::_build_window_id("test-window2", "test"));

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
