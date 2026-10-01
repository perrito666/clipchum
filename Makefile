# Single entry point for building, testing and packaging ClipChum.

APP        := ClipChum
CONFIG     ?= release
BUILD_DIR  := .build/$(CONFIG)
BUNDLE     := dist/$(APP).app
CONTENTS   := $(BUNDLE)/Contents
DMG        ?= dist/$(APP).dmg
ICON_PNG   := Support/AppIcon/icon-1024.png
INSTALL_TO ?= $(HOME)/Applications/$(APP).app
# Ad-hoc by default. For a stable Accessibility grant across rebuilds create a
# self-signed "ClipChum Dev" code-signing certificate in Keychain Access and run
#   make run SIGN_IDENTITY="ClipChum Dev"
# Releases are signed with a Developer ID in CI (see .github/workflows/release.yml).
SIGN_IDENTITY ?= -

.PHONY: build test smoke check app dmg install run icon toggle settings clean

build:
	swift build -c $(CONFIG)

## Unit tests for the core library.
test:
	swift test

## Build the debug binary and run it against a throwaway store.
smoke:
	swift build
	.build/debug/$(APP) --smoke-test

check: test smoke

## A double-clickable application bundle in dist/, with the icon.
app: build
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BUILD_DIR)/$(APP) $(CONTENTS)/MacOS/$(APP)
	cp Support/Info.plist $(CONTENTS)/Info.plist
	plutil -replace CFBundleShortVersionString \
	  -string "$$(git describe --tags --always --dirty 2>/dev/null || echo development)" \
	  $(CONTENTS)/Info.plist
	@for b in $(BUILD_DIR)/*.bundle; do [ -d "$$b" ] && cp -R "$$b" $(CONTENTS)/Resources/ || true; done
	rm -rf dist/$(APP).iconset
	mkdir -p dist/$(APP).iconset
	for size in 16 32 128 256 512; do \
	  sips -z $$size $$size $(ICON_PNG) \
	    --out dist/$(APP).iconset/icon_$${size}x$${size}.png >/dev/null; \
	  sips -z $$((size*2)) $$((size*2)) $(ICON_PNG) \
	    --out dist/$(APP).iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns dist/$(APP).iconset -o $(CONTENTS)/Resources/$(APP).icns
	rm -rf dist/$(APP).iconset
	codesign --force --sign "$(SIGN_IDENTITY)" --timestamp=none $(BUNDLE)
	@echo "Built $(BUNDLE)"

## A drag-to-Applications disk image of the bundle already in dist/. Deliberately
## not dependent on `app`: the release workflow signs the bundle before imaging it.
dmg:
	@test -d $(BUNDLE) || { echo "No $(BUNDLE); run 'make app' first"; exit 1; }
	rm -rf dist/dmg $(DMG)
	mkdir -p dist/dmg
	cp -R $(BUNDLE) dist/dmg/
	ln -s /Applications dist/dmg/Applications
	hdiutil create -volname $(APP) -srcfolder dist/dmg -fs HFS+ -format UDZO -ov $(DMG)
	rm -rf dist/dmg
	@echo "Built $(DMG)"

install: app
	mkdir -p $(dir $(INSTALL_TO))
	rm -rf $(INSTALL_TO)
	cp -R $(BUNDLE) $(INSTALL_TO)

run: install
	-pkill -x $(APP) || true
	open $(INSTALL_TO)

## Re-render the app icon PNG (committed; only needed when the design changes).
icon:
	swiftc -o .build/make-icon scripts/make-icon.swift
	.build/make-icon $(ICON_PNG)

# Open/close the panel or the settings window from a script
# (Darwin notifications; no Accessibility permission needed).
toggle:
	notifyutil -p to.perri.clipchum.toggle

settings:
	notifyutil -p to.perri.clipchum.settings

clean:
	rm -rf .build dist
