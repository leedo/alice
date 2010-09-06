use Test::More;
use App::Alice;
use App::Alice::Test::MockIRC;
use App::Alice::Test::NullHistory;
use Test::TCP;

my $history = App::Alice::Test::NullHistory->new;
my $app = App::Alice->new(
  history => $history,
  standalone => 0,
  path => 't/alice',
  file => "test_config",
  port => empty_port(),
);

my $cl = App::Alice::Test::MockIRC->new(nick => "tester");
$app->config->servers->{"test"} = {
  host => "not.real.server",
  port => 6667,
  autoconnect => 1,
  channels => ["#test"],
  on_connect => ["JOIN #test2"],
};

my $irc = App::Alice::IRC->new(
  alias => "test",
  app => $app,
  cl => $cl,
);
$app->add_irc("test", $irc);

# joining channels
ok $irc->is_connected, "connect";
ok my $window = $app->find_window("#test", $irc), "auto-join channel";
ok $app->find_window("#test2", $irc), "on_connect join command";

# nicks
is $irc->nick, "tester", "nick set";
ok $irc->includes_nick("test"), "existing nick in channel";
is_deeply $irc->get_nick_info("test")->[2], ['#test'], "existing nick info set";

$cl->send_cl(":nick!user\@host JOIN #test");
ok $irc->includes_nick("nick"), "nick added after join";
is_deeply $irc->get_nick_info("nick")->[2], ['#test'], "new nick info set";

$cl->send_cl(":nick!user\@host NICK nick2");
ok $irc->includes_nick("nick2"), "nick change";
ok !$irc->includes_nick("nick"), "old nick removed after nick change";

$cl->send_cl(":nick!user\@host PART #test");
ok !$irc->includes_nick("nick"), "nick gone after part";

# topic
is $window->topic->{string}, "no topic set", "default initial topic";

$cl->send_srv(TOPIC => "#test", "updated topic");
is $window->topic->{string}, "updated topic", "self topic change string";
is $window->topic->{author}, "tester", "self topic change author";

$cl->send_cl(":nick!user\@host TOPIC #test :another topic update");
is $window->topic->{string}, "another topic update", "external topic change string";
is $window->topic->{author}, "nick", "external topic change author";

# part channel
$cl->send_srv(PART => "#test");
ok !$app->find_window("#test", $irc), "part removes window";

# messages
$cl->send_cl(":nick!user\@host PRIVMSG tester :hi");
ok $app->find_window("nick", $irc), "private message";

$cl->send_cl(":nick!user\@host PRIVMSG #test3 :hi");
ok !$app->find_window("#test3", $irc), "msg to unjoined channel doesn't create window";

# disconnect
$cl->disconnect;
ok !$irc->is_connected, "disconnect";

undef $app;
undef $cl;

done_testing();
