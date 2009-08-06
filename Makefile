BUILD := data/static
SOURCE := $(BUILD)/src
INCLUDES := $(SOURCE) $(SOURCE)/alice $(SOURCE)/scriptaculous
INCLUDE := $(foreach dir,$(INCLUDES),-I $(dir))
JAVASCRIPT_SOURCES := $(foreach dir,$(INCLUDES),$(wildcard $(dir)/*.js))

SITE_JS := $(BUILD)/site.js
ALICE_JS := $(SOURCE)/alice/alice.js

all: $(SITE_JS)

$(SITE_JS): $(JAVASCRIPT_SOURCES)
	sprocketize $(INCLUDE) $(ALICE_JS) > $@
