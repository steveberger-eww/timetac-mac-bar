#!/bin/sh
# Builds the drag-to-Applications disk image.
#
#   make-dmg.sh <TimeTacBar.app> <artwork-dir> <output.dmg> <volume-name>
#
# The window layout — icon positions, size, backdrop — lives in a .DS_Store that only Finder can
# write, so this mounts the image and drives Finder to set it. That needs permission to control
# Finder the first time (System Settings → Privacy & Security → Automation). If it's refused the
# image is still produced and still works; it just opens with the default icon layout.

set -eu

APP=$1
ARTWORK=$2
OUTPUT=$3
VOLUME=$4

APP_NAME=$(basename "$APP")
STAGE=$(mktemp -d)
SCRATCH="${TMPDIR:-/tmp}/$VOLUME-rw.dmg"

cleanup() {
	[ -n "${DEVICE:-}" ] && hdiutil detach "$DEVICE" -quiet 2>/dev/null || true
	rm -rf "$STAGE" "$SCRATCH"
}
trap cleanup EXIT

# What the mounted volume will contain: the app, a shortcut to drop it in, and the hidden backdrop.
cp -R "$APP" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp "$ARTWORK/dmg-background.tiff" "$STAGE/.background/background.tiff"

rm -f "$SCRATCH" "$OUTPUT"
hdiutil create -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ \
	-format UDRW -ov "$SCRATCH" -quiet

DEVICE=$(hdiutil attach "$SCRATCH" -readwrite -noverify -noautoopen | grep '^/dev/' | head -1 | awk '{print $1}')
MOUNT="/Volumes/$VOLUME"

# Finder needs a moment after attach before it will answer for the new volume.
sleep 1

if osascript - "$VOLUME" "$APP_NAME" <<'APPLESCRIPT'
on run argv
	set volumeName to item 1 of argv
	set appName to item 2 of argv
	tell application "Finder"
		tell disk volumeName
			open
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			-- 600 wide; the extra height is the title bar, leaving a 600x400 content area to
			-- match the backdrop.
			set the bounds of container window to {200, 120, 800, 548}
			set options to the icon view options of container window
			set arrangement of options to not arranged
			set icon size of options to 128
			set text size of options to 12
			set background picture of options to file ".background:background.tiff"
			set position of item appName of container window to {150, 205}
			set position of item "Applications" of container window to {450, 205}
			close
			open
			update without registering applications
			delay 2
		end tell
	end tell
end run
APPLESCRIPT
then
	echo "  styled the window via Finder"
else
	echo "  ! Finder wouldn't take the layout — the image is fine, just unstyled."
	echo "    Allow Terminal to control Finder under Privacy & Security → Automation and rerun."
fi

# After the styling, not before: Finder swallows .VolumeIcon.icns the moment it opens a volume,
# leaving the custom-icon flag pointing at a file that's no longer there.
cp "$ARTWORK/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
if command -v SetFile > /dev/null 2>&1; then
	SetFile -a C "$MOUNT" || true
fi

chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync

hdiutil detach "$DEVICE" -quiet
DEVICE=""

hdiutil convert "$SCRATCH" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT" -quiet
echo "Wrote $OUTPUT"
