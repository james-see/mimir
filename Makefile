XCODEBUILD := DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild
DERIVED := build/DerivedData

.PHONY: gen build test run clean release package signed-release notarize

gen:
	xcodegen generate

CONFIGURATION ?= Debug

build: gen
	$(XCODEBUILD) -scheme Mimir -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED) build

release:
	$(MAKE) build CONFIGURATION=Release

package: release
	mkdir -p build/dist
	ditto -c -k --sequesterRsrc --keepParent $(DERIVED)/Build/Products/Release/Mimir.app build/dist/Mimir-macOS-arm64.zip

signed-release: release
	python3 tools/release.py

notarize: release
	python3 tools/release.py --notarize

test:
	swift test --package-path MimirCore

run: build
	open $(DERIVED)/Build/Products/Debug/Mimir.app

clean:
	rm -rf build Mimir.xcodeproj MimirCore/.build
