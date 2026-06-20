APP_NAME := RightKeyGesture
BUILD_CONFIG ?= release
APP_DIR := build/$(APP_NAME).app
EXECUTABLE := .build/$(shell uname -m)-apple-macosx/$(BUILD_CONFIG)/$(APP_NAME)
DIST_DIR := dist
ZIP_FILE := $(DIST_DIR)/$(APP_NAME)-macOS-arm64.zip

.PHONY: build app package install run clean

build:
	swift build -c $(BUILD_CONFIG)

app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	cp "$(EXECUTABLE)" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp Resources/*.json "$(APP_DIR)/Contents/Resources/" 2>/dev/null || true
	plutil -convert binary1 "$(APP_DIR)/Contents/Info.plist"
	codesign --force --deep --sign - "$(APP_DIR)"
	@echo "Built $(APP_DIR)"

package: app
	rm -rf "$(DIST_DIR)"
	mkdir -p "$(DIST_DIR)"
	ditto -c -k --norsrc --keepParent "$(APP_DIR)" "$(ZIP_FILE)"
	@echo "Packaged $(ZIP_FILE)"

install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP_DIR)" /Applications/
	@echo "Installed /Applications/$(APP_NAME).app"

run: app
	open "$(APP_DIR)"

clean:
	rm -rf .build build dist
