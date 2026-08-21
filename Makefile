# TimeTacBar — build, bundle, sign and ship the menu bar app.
#
# `swift build` only produces a bare executable; a menu bar app needs a real .app bundle so that
# LSUIElement applies (no Dock icon) and the Keychain has a stable code identity to bind to.

APP_NAME    := TimeTacBar
BUNDLE      := $(APP_NAME).app
BUILD_DIR   := .build
CONFIG      ?= release
BIN         := $(BUILD_DIR)/$(CONFIG)/$(APP_NAME)
CONTENTS    := $(BUNDLE)/Contents
ARTWORK     := $(BUILD_DIR)/artwork
DMG         := $(APP_NAME).dmg
ZIP         := $(APP_NAME).zip

# Local configuration: the company setup to bake in, the signing identity, the notary profile.
# Copy .env.example to .env and fill it in. .env is gitignored — it holds the client secret.
-include .env
export TIMETAC_ACCOUNT TIMETAC_HOST TIMETAC_CLIENT_ID TIMETAC_CLIENT_SECRET

# Ad-hoc by default. An ad-hoc signature is regenerated on every build and the Keychain binds each
# item to the identity that wrote it, so ad-hoc builds re-prompt for Keychain access constantly.
# `make identities` lists what you have.
CODESIGN_IDENTITY ?= -

# Notarisation needs a hardened runtime and a secure timestamp; ad-hoc signing supports neither.
ifeq ($(CODESIGN_IDENTITY),-)
CODESIGN_FLAGS := --timestamp=none
else
CODESIGN_FLAGS := --options runtime --timestamp
endif

# Adds an Info.plist key only when there's a value for it, so an un-baked build simply has none.
# $(1) key, $(2) value
define bake
@if [ -n "$(2)" ]; then \
	/usr/libexec/PlistBuddy -c "Add :$(1) string $(2)" $(CONTENTS)/Info.plist > /dev/null; \
fi
endef

.PHONY: all build artwork bundle run run-mock test probe dmg share notarize release verify \
	identities clean

all: bundle

build:
	swift build -c $(CONFIG)

test:
	swift test

## Icon and disk image backdrop, drawn from Scripts/Artwork.swift so no binaries live in the repo.
artwork: $(ARTWORK)/AppIcon.icns $(ARTWORK)/dmg-background.tiff

$(ARTWORK)/AppIcon.icns: Scripts/Artwork.swift
	@mkdir -p $(BUILD_DIR)
	@swiftc -O Scripts/Artwork.swift -o $(BUILD_DIR)/artwork-gen
	@$(BUILD_DIR)/artwork-gen $(ARTWORK) > /dev/null
	@iconutil -c icns $(ARTWORK)/AppIcon.iconset -o $@
	@echo "Drew $@"

# One file holding both resolutions, so the backdrop isn't soft on a retina display.
$(ARTWORK)/dmg-background.tiff: $(ARTWORK)/AppIcon.icns
	@tiffutil -cathidpicheck $(ARTWORK)/dmg-background.png $(ARTWORK)/dmg-background@2x.png \
		-out $@ 2> /dev/null

bundle: build artwork
	@rm -rf $(BUNDLE)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	@cp $(BIN) $(CONTENTS)/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@cp $(ARTWORK)/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	$(call bake,TTBAccount,$(TIMETAC_ACCOUNT))
	$(call bake,TTBHost,$(TIMETAC_HOST))
	$(call bake,TTBClientID,$(TIMETAC_CLIENT_ID))
	$(call bake,TTBClientSecret,$(TIMETAC_CLIENT_SECRET))
	@printf 'APPL????' > $(CONTENTS)/PkgInfo
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_FLAGS) $(BUNDLE)
	@echo "Built $(BUNDLE)  [$(CODESIGN_IDENTITY)]"
	@if [ -n "$(TIMETAC_ACCOUNT)" ]; then \
		echo "Baked in: $(TIMETAC_ACCOUNT) — sign-in is username + password only."; \
	else \
		echo "Nothing baked in — the app asks for the company setup on first run."; \
	fi

## Launch the bundled app against the live API.
run: bundle
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@open $(BUNDLE)
	@echo "$(APP_NAME) is running — look for it in the menu bar."

## Launch against MockClient: no credentials needed, no network calls.
run-mock: bundle
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@open $(BUNDLE) --env TIMETACBAR_MOCK=1
	@echo "$(APP_NAME) is running in mock mode."

## Read-only connectivity check against a real account. Performs no writes.
probe: build
	@$(BIN) --probe

## Drag-to-Applications disk image.
dmg: bundle
	@sh Scripts/make-dmg.sh $(BUNDLE) $(ARTWORK) $(DMG) "$(APP_NAME)"
	@if [ "$(CODESIGN_IDENTITY)" != "-" ]; then \
		codesign --force --sign "$(CODESIGN_IDENTITY)" --timestamp $(DMG); \
		echo "Signed $(DMG)"; \
	fi

## Zip the bundle instead, if a .dmg is more ceremony than you want.
share: bundle
	@rm -f $(ZIP)
	@ditto -c -k --keepParent $(BUNDLE) $(ZIP)
	@echo "Wrote $(ZIP)"

## Send the disk image to Apple and staple the ticket, so it opens on a double-click.
## Needs a Developer ID Application identity and a stored notary profile — see the README.
notarize: dmg
	@if [ -z "$(NOTARY_PROFILE)" ]; then \
		echo "NOTARY_PROFILE isn't set. Store credentials once with:"; \
		echo "  xcrun notarytool store-credentials TimeTacBar \\"; \
		echo "    --apple-id you@example.com --team-id TEAMID --password <app-specific-password>"; \
		echo "then put NOTARY_PROFILE = TimeTacBar in .env"; \
		exit 1; \
	fi
	@case "$(CODESIGN_IDENTITY)" in \
		"Developer ID Application"*) ;; \
		*) echo "Notarisation needs a 'Developer ID Application' identity."; \
		   echo "CODESIGN_IDENTITY is currently: $(CODESIGN_IDENTITY)"; \
		   echo "Run 'make identities' — an 'Apple Development' certificate will not do."; \
		   exit 1 ;; \
	esac
	xcrun notarytool submit $(DMG) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(DMG)
	@$(MAKE) --no-print-directory verify

## What Gatekeeper will make of the result.
verify:
	@echo "Bundle:"
	@codesign --verify --deep --strict --verbose=1 $(BUNDLE) 2>&1 | sed 's/^/  /' || true
	@spctl --assess --type execute --verbose=2 $(BUNDLE) 2>&1 | sed 's/^/  /' || true
	@if [ -f $(DMG) ]; then \
		echo "Disk image:"; \
		spctl --assess --type open --context context:primary-signature --verbose=2 $(DMG) 2>&1 \
			| sed 's/^/  /' || true; \
		xcrun stapler validate $(DMG) 2>&1 | sed 's/^/  /' || true; \
	fi

## Everything, in order: build, bundle, sign, disk image, notarise, staple, verify.
release: test notarize

identities:
	@security find-identity -v -p codesigning || true

clean:
	@rm -rf $(BUILD_DIR) $(BUNDLE) $(DMG) $(ZIP)
	@echo "Cleaned."
