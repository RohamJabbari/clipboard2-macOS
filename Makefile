APP_NAME   := Clippy
PROJECT    := $(APP_NAME).xcodeproj
SCHEME     := $(APP_NAME)
DERIVED    := build
RELEASE_APP := $(DERIVED)/Build/Products/Release/$(APP_NAME).app
INSTALL_DIR := /Applications

.PHONY: all generate build debug test install run icon pkg clean

# Sign with Developer ID when that certificate exists, so local installs and the .pkg share one
# signature (Accessibility/Keychain grants are tied to it). Otherwise Apple Development.
DEVID_APP := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -c "Developer ID Application")
ifneq ($(DEVID_APP),0)
SIGN_ARGS := CODE_SIGN_IDENTITY="Developer ID Application" OTHER_CODE_SIGN_FLAGS=--timestamp
endif

all: build

generate:
	xcodegen generate --quiet

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS' build -quiet $(SIGN_ARGS)

debug: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS' build -quiet

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS' test -quiet

install: build
	@osascript -e 'tell application id "at.softmaze.Clippy" to quit' >/dev/null 2>&1 || true
	@sleep 1
	@pkill -x $(APP_NAME) >/dev/null 2>&1 || true
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(RELEASE_APP)" "$(INSTALL_DIR)/"
	codesign --verify --strict "$(INSTALL_DIR)/$(APP_NAME).app"
	open "$(INSTALL_DIR)/$(APP_NAME).app"

run: install

pkg:
	scripts/make-pkg.sh

icon:
	swift scripts/make-icon.swift Clippy/Resources/Assets.xcassets/AppIcon.appiconset

clean:
	rm -rf $(DERIVED) $(PROJECT) dist
