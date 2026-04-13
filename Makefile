SHELL = /bin/bash

PROJECT = Mador.xcodeproj
SCHEME = Mador
CONFIGURATION = Debug
DESTINATION = platform=macOS

XCODEBUILD = xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -destination '$(DESTINATION)'

.PHONY: all clean build rebuild app-path reveal reset-accessibility

all: build

clean:
	@if command -v xcbeautify >/dev/null 2>&1; then \
		set -o pipefail; \
		$(XCODEBUILD) clean | xcbeautify; \
	else \
		$(XCODEBUILD) clean; \
	fi

build:
	@if command -v xcbeautify >/dev/null 2>&1; then \
		set -o pipefail; \
		$(XCODEBUILD) build | xcbeautify; \
	else \
		$(XCODEBUILD) build; \
	fi

rebuild:
	$(MAKE) clean
	$(MAKE) build

app-path:
	@eval "$$($(XCODEBUILD) -showBuildSettings | awk -F ' = ' '/TARGET_BUILD_DIR|WRAPPER_NAME/ { print $$1 "=\"" $$2 "\"" }')"; \
	echo "$$TARGET_BUILD_DIR/$$WRAPPER_NAME"

reveal:
	@eval "$$($(XCODEBUILD) -showBuildSettings | awk -F ' = ' '/TARGET_BUILD_DIR|WRAPPER_NAME/ { print $$1 "=\"" $$2 "\"" }')"; \
	open -R "$$TARGET_BUILD_DIR/$$WRAPPER_NAME"

reset-accessibility:
	tccutil reset Accessibility org.kakera.Mador
