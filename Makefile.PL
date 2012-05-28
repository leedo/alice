use inc::Module::Install;
name 'Alice';
perl_version '5.008';
author 'Lee Aylward <leedo@cpan.org>';
all_from 'lib/Alice.pm';
license 'perl';

requires 'Class::Throwable';
requires 'List::MoreUtils';
requires 'Any::Moose';
requires 'Try::Tiny';
requires 'EV';
requires 'AnyEvent' => '5.2';
requires 'AnyEvent::AIO';
requires 'AnyEvent::IRC' => '0.95';
requires 'AnyEvent::HTTP';
requires 'Fliggy';
requires 'Plack';
requires 'Plack::Session';
requires 'DBD::SQLite';
requires 'SQL::Abstract';
requires 'AnyEvent::DBI';
requires 'IRC::Formatting::HTML' => '0.28';
requires 'Text::MicroTemplate' => '0.09';
requires 'JSON' => '2.12';
requires 'File::ShareDir';
requires 'File::Copy';
requires 'Net::SSLeay';
requires 'Protocol::WebSocket' => '0.00906';

test_requires 'Test::More' => '0.86';
test_requires 'Test::TCP' => '0';
install_share 'share';
install_script 'bin/alice';

postamble q{
BUILD := share/static
SOURCE := src
JS_SOURCE := $(SOURCE)/js
CSS_SOURCE := $(SOURCE)/css
JS_DEPS := prototype scriptaculous effects dragdrop shortcut sprintf swfobject web_socket wysihat
EXT_JS := $(foreach dep,$(JS_DEPS),$(JS_SOURCE)/external/$(dep).js)
ALICE_JS := $(JS_SOURCE)/alice.js $(JS_SOURCE)/alice/*.js $(JS_SOURCE)/load.js

ALICE_SCSS := $(CSS_SOURCE)/alice.scss
SITE_JS := $(BUILD)/alice.js

COLORFILES := $(foreach dir,$(CSS_SOURCE)/colors,$(wildcard $(dir)/*.scss))
CSSFILES := $(addprefix $(BUILD)/alice-,$(notdir $(COLORFILES:.scss=.css)))

$(BUILD)/alice-%.css: $(CSS_SOURCE)/colors/%.scss $(ALICE_SCSS)
	cat $< $(ALICE_SCSS) | sass --scss -s $@

assets: stylesheets javascript

stylesheets: $(CSSFILES)

javascript: $(EXT_JS) $(ALICE_JS)
	cat $(EXT_JS) $(ALICE_JS) > $(SITE_JS)
};

WriteAll;
