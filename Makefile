XCODEBUILD := DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild
DERIVED := build/DerivedData

.PHONY: gen build test run clean

gen:
	xcodegen generate

build: gen
	$(XCODEBUILD) -scheme Mimir -configuration Debug -derivedDataPath $(DERIVED) build

test:
	swift test --package-path MimirCore

run: build
	open $(DERIVED)/Build/Products/Debug/Mimir.app

clean:
	rm -rf build Mimir.xcodeproj MimirCore/.build
