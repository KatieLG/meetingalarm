PROJECT := MeetingAlarm.xcodeproj
SCHEME := MeetingAlarm
DERIVED := build
APP := $(DERIVED)/Build/Products/Debug/MeetingAlarm.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(DERIVED)

.PHONY: gen build test run clean

gen:
	xcodegen generate

build: gen
	$(XCODEBUILD) -configuration Debug build

test: gen
	$(XCODEBUILD) test

run: build
	-pkill -x MeetingAlarm
	open $(APP)

clean:
	rm -rf $(DERIVED) $(PROJECT)
