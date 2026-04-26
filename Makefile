-include .env

VCPKG_ROOT  ?= $(HOME)/vcpkg
TOOLCHAIN   := $(VCPKG_ROOT)/scripts/buildsystems/vcpkg.cmake

APP_NAME    := Zuma Portable
DMG_NAME    := ZumaPortable
BUILD_ARM64 := build
BUILD_X64   := build-x64
APP_ARM64   := $(BUILD_ARM64)/zuma-portable.app
APP_X64     := $(BUILD_X64)/zuma-portable.app
STAGING     := $(BUILD_ARM64)/dmg_staging
APP_OUT     := $(STAGING)/$(APP_NAME).app
DMG         := $(BUILD_ARM64)/$(DMG_NAME).dmg

CMAKE_FLAGS := -DCMAKE_BUILD_TYPE=Release \
               -DCMAKE_TOOLCHAIN_FILE=$(TOOLCHAIN) \
               -DCMAKE_FIND_FRAMEWORK=LAST

JOBS := $(shell sysctl -n hw.ncpu)

.PHONY: all arm64 x64 app dmg release clean

all: dmg

arm64: src/CircleShoot src/SexyAppFrameworkFlat
	cmake -S . -B $(BUILD_ARM64) $(CMAKE_FLAGS) \
		-DVCPKG_TARGET_TRIPLET=arm64-osx -DCMAKE_OSX_ARCHITECTURES=arm64
	cmake --build $(BUILD_ARM64) -j$(JOBS)

x64: src/CircleShoot src/SexyAppFrameworkFlat
	cmake -S . -B $(BUILD_X64) $(CMAKE_FLAGS) \
		-DVCPKG_TARGET_TRIPLET=x64-osx -DCMAKE_OSX_ARCHITECTURES=x86_64
	cmake --build $(BUILD_X64) -j$(JOBS)

src/CircleShoot:
	git clone https://github.com/kyle-sylvestre/CircleShootApp.git $@

src/SexyAppFrameworkFlat: src/CircleShoot
	bash scripts/create_flat_directory.sh
	@ln -sf XMLParser.h src/SexyAppFrameworkFlat/SexyAppFramework/XmlParser.h

define lipo_app
	rm -rf $(STAGING)
	mkdir -p $(STAGING)
	cp -R $(APP_ARM64) "$(APP_OUT)"
	lipo -create \
		$(APP_ARM64)/Contents/MacOS/zuma-portable \
		$(APP_X64)/Contents/MacOS/zuma-portable \
		-output "$(APP_OUT)/Contents/MacOS/zuma-portable"
endef

define build_dmg
	rm -f $(1)
	ln -s /Applications $(STAGING)/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(STAGING) -ov -format UDZO $(1)
	rm -f $(STAGING)/Applications
endef

app: arm64 x64
	$(lipo_app)
	codesign --force --sign - "$(APP_OUT)"

dmg: app
	$(call build_dmg,$(DMG))
	@echo "Built $(DMG)"

release: arm64 x64
	@test -n "$(DEV_ID)" || { echo "DEV_ID not set — copy .env.example to .env and fill in"; exit 1; }
	@test -n "$(NOTARY_PROFILE)" || { echo "NOTARY_PROFILE not set — copy .env.example to .env and fill in"; exit 1; }
	$(lipo_app)
	codesign --force --options runtime --timestamp --sign "$(DEV_ID)" "$(APP_OUT)"
	$(call build_dmg,$(DMG))
	codesign --force --timestamp --sign "$(DEV_ID)" $(DMG)
	xcrun notarytool submit $(DMG) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(DMG)
	@echo "Signed + notarized: $(DMG)"

clean:
	rm -rf $(BUILD_ARM64) $(BUILD_X64)
