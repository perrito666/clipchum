APP        := ClipChum
CONFIG     ?= release
BUILD_DIR  := .build/$(CONFIG)
BUNDLE     := build/$(APP).app
CONTENTS   := $(BUNDLE)/Contents
INSTALL_TO ?= $(HOME)/Applications/$(APP).app
# Ad-hoc by default. For a stable Accessibility grant across rebuilds create a
# self-signed "ClipChum Dev" code-signing certificate in Keychain Access and run
#   make run SIGN_IDENTITY="ClipChum Dev"
SIGN_IDENTITY ?= -

.PHONY: build app install run test clean toggle settings

build:
	swift build -c $(CONFIG)

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BUILD_DIR)/$(APP) $(CONTENTS)/MacOS/$(APP)
	cp Support/Info.plist $(CONTENTS)/Info.plist
	@for b in $(BUILD_DIR)/*.bundle; do [ -d "$$b" ] && cp -R "$$b" $(CONTENTS)/Resources/ || true; done
	codesign --force --sign "$(SIGN_IDENTITY)" --timestamp=none $(BUNDLE)

install: app
	mkdir -p $(dir $(INSTALL_TO))
	rm -rf $(INSTALL_TO)
	cp -R $(BUNDLE) $(INSTALL_TO)

run: install
	-pkill -x $(APP) || true
	open $(INSTALL_TO)

test:
	swift test

clean:
	rm -rf .build build

# Open/close the panel from a script (no Accessibility permission needed).
toggle:
	notifyutil -p eu.dumontix.clipchum.toggle

settings:
	notifyutil -p eu.dumontix.clipchum.settings
