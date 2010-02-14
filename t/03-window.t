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

my $irc = $app->ircs->{test};

my $window = $app->create_window("test-window", $irc);
ok $window->type eq "privmsg", "correct window type for privmsg";
ok !$window->is_channel, "is_channel for privmsg";
$app->remove_window($window->id);

$window = $app->create_window("#test-window", $irc);

ok $window->type eq "channel", "correct window type for channel";
ok $window->is_channel, "is_channel for channel";
is $window->title, "#test-window", "window title";
is $window->nick, "tester", "nick";
is $window->topic->{string}, "no topic set", "default window topic";

is_deeply $window->serialized, {
  id => "win_testwindowtest",
  session => "test",
  title => "#test-window",
  is_channel => 1,
  type => "channel",
}, "serialize window";

$window->add_message({}) for (0 .. 110);
is scalar @{$window->msgbuffer}, $window->buffersize, "max message buffer size";
$window->clear_buffer;
is scalar @{$window->msgbuffer}, 0, "clear message buffer";

done_testing();