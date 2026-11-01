APP = build/Build/Products/Debug/Retouche.app

.PHONY: build run test eval snapshots dmg site clean

build:
	xcodebuild -project Retouche.xcodeproj -scheme Retouche -configuration Debug -derivedDataPath build build | xcbeautify 2>/dev/null || \
	xcodebuild -project Retouche.xcodeproj -scheme Retouche -configuration Debug -derivedDataPath build build -quiet

run: build
	-pkill -x Retouche
	open $(APP)

# Unit tests for the correction engine and typing session.
test:
	cd Packages/RetoucheKit && swift test

# Types French/English sentences through the real engine and reports accuracy and latency.
# STRENGTH=cautious|balanced|bold picks the correction strength (balanced by default).
# IA=1 sends ambiguous words to Apple Intelligence, as the app does (Xcode 26+).
eval:
	cd Packages/RetoucheKit && swift run -c release retouche-eval $(STRENGTH) $(if $(IA),--ia)

# Renders the menu, overlay and settings to PNG (Debug builds only).
snapshots: build
	mkdir -p build/snapshots
	RETOUCHE_SNAPSHOTS=$(CURDIR)/build/snapshots $(APP)/Contents/MacOS/Retouche
	open build/snapshots

# Universal Release build in build/Retouche.dmg, the file attached to each GitHub release.
dmg:
	xcodebuild -project Retouche.xcodeproj -scheme Retouche -configuration Release -derivedDataPath build -destination 'generic/platform=macOS' build -quiet
	rm -rf build/dmg build/Retouche.dmg
	mkdir -p build/dmg
	ditto build/Build/Products/Release/Retouche.app build/dmg/Retouche.app
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname Retouche -srcfolder build/dmg -format UDZO build/Retouche.dmg

# The presentation page and its animated demo, on http://127.0.0.1:5180.
site:
	cd Site && npm install && npm run dev -- --port 5180

clean:
	rm -rf build Packages/RetoucheKit/.build Site/dist
