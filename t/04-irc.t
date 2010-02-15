use Test::More;
use App::Alice;
use App::Alice::Test::MockIRC;

my $app = App::Alice->new(
  standalone => 0, path => 't', file => "test_config");

my $irc = App::Alice::IRC->new(
  alias => "test",
  config => {
    host => "not.real.server",
    port => 6667,
    autoconnect => 1,
    channels => ["#test"],
    on_connect => ["JOIN #test2"],
  },
  app => $app,
  cl => App::Alice::Test::MockIRC->new(nick => "tester"),
);
$app->ircs->{test} = $irc;

# joining channels
ok $irc->is_connected, "connect";
ok my $window = $app->find_window("#test", $irc), "auto-join channel";
ok $app->find_window("#test2", $irc), "on_connect join command";

# nicks
is $irc->nick, "tester", "nick set";
ok $irc->includes_nick("test"), "existing nick in channel";
$irc->cl->simulate_line(":nick!user\@host JOIN #test");
ok $irc->includes_nick("nick"), "nick after join";

# topic changes
$irc->cl->send_srv(TOPIC => "#test", "updated topic");
is $window->topic->{string}, "updated topic", "self topic change string";
is $window->topic->{author}, "tester", "self topic change author";

$irc->cl->simulate_line(":nick!user\@host TOPIC #test :another topic update\015\012");
is $window->topic->{string}, "another topic update", "external topic change string";
is $window->topic->{author}, "nick", "external topic change author";

# part channel
$irc->cl->simulate_line(":nick!user\@host PART #test");
ok !$irc->includes_nick("nick"), "nick gone after part";
$irc->cl->send_srv(PART => "#test");
ok !$app->find_window("#test", $irc), "part removes window";

# disconnect
$irc->cl->disconnect;
ok !$irc->is_connected, "disconnect";

done_testing();

