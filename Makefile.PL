use inc::Module::Install;
name 'App-Alice';
perl_version '5.008';
author 'Lee Aylward <leedo@cpan.org>';
all_from 'lib/App/Alice.pm';
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
requires 'IRC::Formatting::HTML' => '0.17';
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
SOURCE := share/sprockets
SPROCKETS := alice prototype scriptaculous shortcut iscroll
INCLUDES := $(foreach sprocket,$(SPROCKETS),$(SOURCE)/$(sprocket)/src)
INCLUDE := $(foreach dir,$(INCLUDES),-I $(dir))
JAVASCRIPT_SOURCES := $(foreach dir,$(INCLUDES),$(wildcard $(dir)/*.js))

SITE_JS := $(BUILD)/alice.js
MIN_JS := $(BUILD)/alice-min.js
ALICE_JS := $(SOURCE)/alice/src/alice.js

define build_submodules
	sh -c "git submodule init && git submodule update"
endef

javascript: $(SITE_JS) compressed

$(SITE_JS): $(JAVASCRIPT_SOURCES) submodules
	sprocketize $(INCLUDE) $(ALICE_JS) > $@

compressed:
	yuicompressor $(SITE_JS) > $(MIN_JS)

$(SOURCE)/prototype/.git/refs/heads/master:
	$(build_submodules)
$(SOURCE)/scriptaculous/.git/refs/heads/master:
	$(build_submodules)

submodules: $(SOURCE)/prototype/.git/refs/heads/master $(SOURCE)/scriptaculous/.git/refs/heads/master
};

WriteAll;
