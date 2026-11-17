APP    = MemBar
BUNDLE = dist/$(APP).app
BIN    = .build/release/$(APP)
ID     = dev.tss.MemBar

.PHONY: run build test bundle install clean

run:
	swift run

build:
	swift build -c release

test:
	swift test

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force -s - --identifier $(ID) $(BUNDLE)

install: bundle
	rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/
	@echo "Installed. Launch with: open /Applications/$(APP).app"

clean:
	rm -rf .build dist
