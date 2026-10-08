APP_NAME   := Clippy
PROJECT    := $(APP_NAME).xcodeproj
SCHEME     := $(APP_NAME)
DERIVED    := build
RELEASE_APP := $(DERIVED)/Build/Products/Release/$(APP_NAME).app
INSTALL_DIR := /Applications

.PHONY: all generate build debug test install run icon clean

all: build

generate:
	xcodegen generate --quiet

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS' build -quiet

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

icon:
	swift scripts/make-icon.swift Clippy/Resources/Assets.xcassets/AppIcon.appiconset

clean:
	rm -rf $(DERIVED) $(PROJECT)
