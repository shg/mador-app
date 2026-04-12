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
	@TARGET_BUILD_DIR=`$(XCODEBUILD) -showBuildSettings | awk -F ' = ' '/TARGET_BUILD_DIR/ { print $$2; exit }'`; \
	WRAPPER_NAME=`$(XCODEBUILD) -showBuildSettings | awk -F ' = ' '/WRAPPER_NAME/ { print $$2; exit }'`; \
	echo "$$TARGET_BUILD_DIR/$$WRAPPER_NAME"

reveal:
	@TARGET_BUILD_DIR=`$(XCODEBUILD) -showBuildSettings | awk -F ' = ' '/TARGET_BUILD_DIR/ { print $$2; exit }'`; \
	WRAPPER_NAME=`$(XCODEBUILD) -showBuildSettings | awk -F ' = ' '/WRAPPER_NAME/ { print $$2; exit }'`; \
	open -R "$$TARGET_BUILD_DIR/$$WRAPPER_NAME"

reset-accessibility:
	tccutil reset Accessibility org.kakera.Mador
