use Test::More;
use App::Alice;
use App::Alice::Test::MockIRC;

my $app = App::Alice->new(
  standalone => 0, path => 't', file => "test_config");

my $irc = App::Alice::IRC->new(
  alias => "test",
  config => {
    nick => "tester",
    host => "not.real.server",
    port => 6667,
    autoconnect => 1,
    channels => ["#test"],
  },
  app => $app,
  cl => App::Alice::Test::MockIRC->new(nick => "tester"),
);
$app->ircs->{test} = $irc;

ok $irc->is_connected, "connect";
ok $app->find_window("#test", $irc), "auto-join channel";
is_deeply [$irc->all_nicks], ["tester"], "nick list";

$irc->cl->disconnect;
ok !$irc->is_connected, "disconnect";

done_testing();

