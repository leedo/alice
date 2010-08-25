use inc::Module::Install;
name 'App-Alice';
perl_version '5.008';
author 'Lee Aylward <leedo@cpan.org>';
all_from 'lib/App/Alice.pm';
requires 'List::MoreUtils' => '0';
requires 'Any::Moose' => '0';
requires 'Try::Tiny' => '0';
requires 'AnyEvent' => '5.2';
requires 'AnyEvent::IRC' => '0.95';
requires 'AnyEvent::HTTP' => '0';
requires 'Twiggy' => '0';
requires 'Plack' => '0';
requires 'Plack::Session' => '0';
requires 'DBD::SQLite' => '0';
requires 'SQL::Abstract' => '0';
requires 'AnyEvent::DBI' => '0';
requires 'IRC::Formatting::HTML' => '0.27';
requires 'Text::MicroTemplate' => '0.09';
requires 'JSON' => '2.12';
requires 'File::ShareDir' => '0.01';
requires 'File::Copy' => '0';
test_requires 'Test::More' => '0.86';
test_requires 'Test::TCP' => '0';
install_share 'share';
install_script 'bin/alice';
no_index 'directory' => 'share/sprockets';

postamble q{
BUILD := share/static
SOURCE := src
JS_SOURCE := $(SOURCE)/js
CSS_SOURCE := $(SOURCE)/css
SPROCKETS := alice prototype scriptaculous shortcut iscroll wysihat sprintf
INCLUDES := $(foreach sprocket,$(SPROCKETS),$(JS_SOURCE)/$(sprocket)/src)
INCLUDE := $(foreach dir,$(INCLUDES),-I $(dir))
JAVASCRIPT_SOURCES := $(foreach dir,$(INCLUDES),$(wildcard $(dir)/*.js))

CAN_COMPRESS := `which yuicompressor`

ALICE_CSS := $(CSS_SOURCE)/alice.css
SITE_CSS := $(BUILD)/alice.css
ALICE_JS := $(JS_SOURCE)/alice/src/alice.js
SITE_JS := $(BUILD)/alice.js

clean_assets:
	rm $(BUILD)/*.css
	rm $(BUILD)/*.js

assets: stylesheets javascript
		
stylesheets:
	cp $(ALICE_CSS) $(SITE_CSS)
  
javascript: $(JAVASCRIPT_SOURCES)
	sprocketize $(INCLUDE) $(ALICE_JS) > $(SITE_JS)
};

WriteAll;
