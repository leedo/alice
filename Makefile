BUILD := data/static
SOURCE := data/sprockets
INCLUDES := $(SOURCE)/alice/src $(SOURCE)/prototype/src $(SOURCE)/scriptaculous/src
INCLUDE := $(foreach dir,$(INCLUDES),-I $(dir))
JAVASCRIPT_SOURCES := $(foreach dir,$(INCLUDES),$(wildcard $(dir)/*.js))

SITE_JS := $(BUILD)/site.js
ALICE_JS := $(SOURCE)/alice/src/alice.js

$(SITE_JS): $(JAVASCRIPT_SOURCES) submodules
	sprocketize $(INCLUDE) $(ALICE_JS) > $@

$(SOURCE)/prototype/src: submodule
$(SOURCE)/scriptaculous/src: submodule

all: $(SITE_JS)

submodules: $(SOURCE)/prototype/src $(SOURCE)/scriptaculous/src

submodule:
	git submodule init
	git submodule update

clean:
	rm -f $(SITE_JS)
