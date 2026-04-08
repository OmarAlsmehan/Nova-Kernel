#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

ZIP_DIR="$PACKAGE_BASE/.zip-staging"
IMG_DIR="$ZIP_DIR/images"
META_DIR="$ZIP_DIR/META-INF/com/google/android"
rm -rf "$ZIP_DIR"
mkdir -p "$IMG_DIR" "$META_DIR"

curl -fsSL "${AK3_BANNER_URL:?AK3_BANNER_URL is required}" -o "$ZIP_DIR/banner"
cp "$PACKAGE_BASE/boot.img" "$IMG_DIR/boot.img"
cp "$PACKAGE_BASE/dtbo.img" "$IMG_DIR/dtbo.img"
cp "$PACKAGE_BASE/vendor_boot.img" "$IMG_DIR/vendor_boot.img"

cat > "$META_DIR/updater-script" <<'UPDATER_EOF'
# Dummy file; update-binary is a shell script.
UPDATER_EOF

cat > "$META_DIR/update-binary" <<'FLASH_EOF'
#!/sbin/sh

OUTFD=/proc/self/fd/$2
ZIPFILE="$3"
TMPDIR="/cache/nova"

package_extract_dir() {
    local entry outfile
    for entry in $(unzip -l "$ZIPFILE" 2>/dev/null | tail -n+4 | grep -v '/$' | grep -o " $1.*$" | cut -c2-); do
        outfile="$(echo "$entry" | sed "s|${1}|${2}|")"
        mkdir -p "$(dirname "$outfile")"
        unzip -o "$ZIPFILE" "$entry" -p > "$outfile"
    done
}

ui_print() {
    while [ "$1" ]; do
        echo "ui_print $1" >> "$OUTFD"
        echo "ui_print" >> "$OUTFD"
        shift
    done
}

ui_printfile() {
    unzip -p "$ZIPFILE" "$1" 2>/dev/null | while IFS= read -r line; do
        ui_print "$line"
    done
}

write_raw_image() {
    dd if="$1" of="$2"
}

set_progress() {
    echo "set_progress $1" >> "$OUTFD"
}

set_progress 0
ui_printfile "banner"
ui_print " "
ui_print " "

if ! getprop ro.boot.bootloader | grep -qE "A736|A528|M526"; then
    ui_print "✖ Unsupported device — aborting."
    exit 1
fi

mount -o rw,remount -t auto /cache
mkdir -p "$TMPDIR"

ui_print "→ Extracting images..."
package_extract_dir "images" "$TMPDIR/"
set_progress 0.2

ui_print "→ Flashing boot.img..."
write_raw_image "$TMPDIR/boot.img" "/dev/block/bootdevice/by-name/boot"
set_progress 0.4

ui_print "→ Flashing dtbo.img..."
write_raw_image "$TMPDIR/dtbo.img" "/dev/block/bootdevice/by-name/dtbo"
set_progress 0.6

ui_print "→ Flashing vendor_boot.img..."
write_raw_image "$TMPDIR/vendor_boot.img" "/dev/block/bootdevice/by-name/vendor_boot"
set_progress 0.8

rm -rf "$TMPDIR"
set_progress 1.0

ui_print " "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  Done! __KERNEL_NAME__ installed successfully."
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
FLASH_EOF
sed -i "s/__KERNEL_NAME__/${KERNEL_NAME:?KERNEL_NAME is required}/" "$META_DIR/update-binary"
chmod +x "$META_DIR/update-binary"

: "${ZIP_NAME:?ZIP_NAME must be set by main.sh before calling this script}"
ZIP_PATH="$PACKAGE_BASE/$ZIP_NAME"
(
    cd "$ZIP_DIR"
    zip -r -9 "$ZIP_PATH" images META-INF banner
)
rm -rf "$ZIP_DIR"

export ZIP_PATH ZIP_NAME
printf 'ZIP_PATH=%s\n' "$ZIP_PATH" >> "$GITHUB_ENV"
printf 'ZIP_NAME=%s\n' "$ZIP_NAME" >> "$GITHUB_ENV"
printf 'PACKAGE_MODE=GKI\n' >> "$GITHUB_ENV"

echo "✅ GKI package created"
