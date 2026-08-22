#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-v0.3.6}"
INCLUDE_IMAGES="${INCLUDE_IMAGES:-1}"
DIST_DIR="${DIST_DIR:-$BASE_DIR/dist}"
FULL_ARCHIVE="${FULL_ARCHIVE:-$BASE_DIR/../termux-ath9k-vm-release-work/termux-ath9k-vm-ready.tar.gz}"
OLD_UNIFIED_ARCHIVE="${OLD_UNIFIED_ARCHIVE:-$BASE_DIR/dist/termux-ath9k-vm-full-lite-ready.tar.gz}"
LITE_BUILD_DIR="${LITE_BUILD_DIR:-$BASE_DIR/../termux-ath9k-vm-v031-lite-build/guest}"
KERNEL_DIR="${KERNEL_DIR:-$BASE_DIR/../termux-ath9k-vm-v031-guest}"
OUT="${OUT:-$DIST_DIR/termux-ath9k-vm-v036-full-lite-ready.tar.gz}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/termux-ath9k-v035-unified.XXXXXX")"
ROOT="$STAGE/termux-ath9k-vm-full-lite"
cleanup(){ rm -rf -- "$STAGE"; }
trap cleanup EXIT INT TERM

die(){ echo "ERROR: $*" >&2; exit 1; }
for f in "$FULL_ARCHIVE" "$OLD_UNIFIED_ARCHIVE"; do [ -s "$f" ] || die "Input archive not found: $f"; done
for f in \
  "$LITE_BUILD_DIR/alpine-ath9k-v031-lite.img" \
  "$LITE_BUILD_DIR/vmlinuz-lts-lite" \
  "$LITE_BUILD_DIR/initramfs-lts-lite" \
  "$KERNEL_DIR/vmlinuz-tiny" \
  "$KERNEL_DIR/vmlinuz-safe"; do
  [ -s "$f" ] || die "required Lite artifact not found for $VERSION: $f"
done
mkdir -p "$DIST_DIR"

# Start from the previously published combined archive so the nested Full and
# all legacy launcher/recovery files remain unchanged, then replace Lite only.
tar -xzf "$OLD_UNIFIED_ARCHIVE" -C "$STAGE"
[ -d "$ROOT/full" ] || die 'Existing combined archive has no full/ directory'
[ -d "$ROOT/lite" ] || die 'Existing combined archive has no lite/ directory'

# Replace the old combined Full directory with a byte-for-byte extraction of
# the canonical published Full archive. This prevents convenience checksums or
# any other unified-release helper from changing Full semantics.
rm -rf "$ROOT/full"
mkdir -p "$ROOT/full"
tar -xzf "$FULL_ARCHIVE" -C "$ROOT/full" --strip-components=1

# Apply the console login-shell fix to the Full image and its maintenance
# scripts. This is a direct root shell, not a login manager, so no password
# prompt is introduced.
CREATE_BACKUP=0 "$BASE_DIR/src/patch-console-login-shell.sh" "$ROOT/full/guest/alpine-ath9k.img"
CREATE_BACKUP=0 "$BASE_DIR/src/configure-console-auth.sh" "$ROOT/full/guest/alpine-ath9k.img" root-console
e2fsck -fn "$ROOT/full/guest/alpine-ath9k.img" >/dev/null
if [ -f "$ROOT/full/src/build-image.sh" ]; then
  sed -E -i 's|^ttyAMA0::respawn:/bin/sh([[:space:]]+-l)?[[:space:]]*$|ttyAMA0::respawn:/bin/sh -l|' "$ROOT/full/src/build-image.sh"
  python3 "$BASE_DIR/src/patch-full-builder-shadow.py" "$ROOT/full/src/build-image.sh"
fi
if [ -f "$ROOT/full/src/enable-root-autologin.sh" ]; then
  sed -i \
    -e 's#ttyAMA0::respawn:/bin/sh|#ttyAMA0::respawn:/bin/sh -l|#g' \
    -e "s|ttyAMA0::respawn:/bin/sh'|ttyAMA0::respawn:/bin/sh -l'|g" \
    -e 's|ttyAMA0::respawn:/bin/sh$|ttyAMA0::respawn:/bin/sh -l|' \
    "$ROOT/full/src/enable-root-autologin.sh"
fi
# Keep the nested Full manual and rescue launchers writable as well as the
# unified adapter. Alpine's initramfs otherwise defaults to -o ro.
for launcher in "$ROOT/full/bin/launch-vm.sh" "$ROOT/full/bin/launch-vm-rescue.sh"; do
  [ -f "$launcher" ] || continue
  sed -E -i 's|root=/dev/vda rw rootfstype=ext4|root=/dev/vda rw rootflags=rw rootfstype=ext4|g' "$launcher"
done

# Replace only Lite guest artifacts. Keep the historical internal image name
# for launcher compatibility while using the patched Lite contents.
rm -f "$ROOT/lite/guest/alpine-ath9k-v030-lite.img" "$ROOT/lite/guest/vmlinuz-tiny" "$ROOT/lite/guest/vmlinuz-safe" "$ROOT/lite/guest/vmlinuz-lts-lite" "$ROOT/lite/guest/initramfs-lts-lite"
cp --sparse=always "$LITE_BUILD_DIR/alpine-ath9k-v031-lite.img" "$ROOT/lite/guest/alpine-ath9k-v030-lite.img"
CREATE_BACKUP=0 "$BASE_DIR/src/patch-console-login-shell.sh" "$ROOT/lite/guest/alpine-ath9k-v030-lite.img"
CREATE_BACKUP=0 "$BASE_DIR/src/configure-console-auth.sh" "$ROOT/lite/guest/alpine-ath9k-v030-lite.img" root-console
e2fsck -fn "$ROOT/lite/guest/alpine-ath9k-v030-lite.img" >/dev/null
cp -p "$KERNEL_DIR/vmlinuz-tiny" "$KERNEL_DIR/vmlinuz-safe" "$LITE_BUILD_DIR/vmlinuz-lts-lite" "$LITE_BUILD_DIR/initramfs-lts-lite" "$ROOT/lite/guest/"

# Use the corrected Lite scripts, patched guest consoles, and v0.3.6 documentation.
rm -f "$ROOT/docs/LITE-v0.3.1.md" "$ROOT/docs/RELEASE-v0.3.1.md" "$ROOT/docs/LITE-v0.3.3.md" "$ROOT/docs/RELEASE-v0.3.3.md" "$ROOT/docs/LITE-v0.3.4.md" "$ROOT/docs/RELEASE-v0.3.4.md" "$ROOT/docs/LITE-v0.3.6.md" "$ROOT/docs/RELEASE-v0.3.6.md"
cp -p "$BASE_DIR/docs/LITE-v0.3.6.md" "$ROOT/lite/README.md"
cp -p "$BASE_DIR/README-UNIFIED.md" "$ROOT/README.md"
cp -p "$BASE_DIR/bin/vm-launcher.sh" "$ROOT/bin/vm-launcher.sh"
cp -p "$BASE_DIR/bin/vm-launcher-unified.sh" "$ROOT/bin/vm-launcher-unified.sh"
cp -p "$BASE_DIR/bin/vm-launcher-legacy.sh" "$ROOT/bin/vm-launcher-legacy.sh"
cp -p "$BASE_DIR/bin/launch-vm-full-unified.sh" "$ROOT/bin/launch-vm-full-unified.sh"
cp -p "$BASE_DIR/bin/vmctl.sh" "$BASE_DIR/bin/vm-backup.sh" "$BASE_DIR/bin/vm-export.sh" "$BASE_DIR/bin/vm-import.sh" "$ROOT/bin/"
cp -p "$BASE_DIR/src/install-termux-unified.sh" "$ROOT/bin/install-termux.sh"
mkdir -p "$ROOT/src"
cp -p "$BASE_DIR/src/configure-console-auth.sh" "$BASE_DIR/src/vm-storage-lib.sh" "$BASE_DIR/src/patch-full-builder-shadow.py" "$ROOT/src/"
cp -p "$BASE_DIR/bin/launch-vm-lite.sh" "$BASE_DIR/bin/qemu-lite-direct-inner.sh" "$BASE_DIR/bin/usb-attach-lite-direct.sh" "$ROOT/lite/bin/"
cp -p "$BASE_DIR/src/build-lite-image.sh" "$BASE_DIR/src/guest-install-wifi-tools.sh" "$BASE_DIR/src/package-lite-release.sh" "$BASE_DIR/src/build-kernel-tiers.sh" "$BASE_DIR/src/verify-kernel-tiers.sh" "$BASE_DIR/src/patch-console-login-shell.sh" "$BASE_DIR/src/configure-console-auth.sh" "$BASE_DIR/src/vm-storage-lib.sh" "$ROOT/lite/src/"
mkdir -p "$ROOT/full/src"
cp -p "$BASE_DIR/src/configure-console-auth.sh" "$BASE_DIR/src/vm-storage-lib.sh" "$ROOT/full/src/"
cp -p "$BASE_DIR/docs/LITE-v0.3.6.md" "$BASE_DIR/docs/RELEASE-v0.3.6.md" "$BASE_DIR/docs/UNIFIED-RELEASE.md" "$ROOT/docs/"
chmod +x "$ROOT/bin/"*.sh "$ROOT/src/"*.sh "$ROOT/lite/bin/"*.sh "$ROOT/lite/src/"*.sh "$ROOT/full/src/"*.sh

(
  cd "$ROOT/lite/guest"
  sha256sum alpine-ath9k-v030-lite.img vmlinuz-tiny vmlinuz-safe vmlinuz-lts-lite initramfs-lts-lite > SHA256SUMS
)
(
  cd "$ROOT/lite/guest"
  sha256sum alpine-ath9k-v030-lite.img vmlinuz-tiny vmlinuz-safe vmlinuz-lts-lite initramfs-lts-lite > SHA256SUMS-v0.3.6-lite
)

if [ "$INCLUDE_IMAGES" = 0 ]; then
  find "$ROOT/full/guest" "$ROOT/lite/guest" -maxdepth 1 -type f -name '*.img' -delete
  (
    cd "$ROOT/full/guest"
    sha256sum vmlinuz-lts initramfs-lts > SHA256SUMS
  )
  (
    cd "$ROOT/lite/guest"
    sha256sum vmlinuz-tiny vmlinuz-safe vmlinuz-lts-lite initramfs-lts-lite > SHA256SUMS
    sha256sum vmlinuz-tiny vmlinuz-safe vmlinuz-lts-lite initramfs-lts-lite > SHA256SUMS-v0.3.6-update
  )
  printf 'Thin update mode: writable guest images excluded; use VM_LEGACY_DIR or existing persistent storage.\n'
fi

rm -f -- "$OUT" "$OUT.sha256"
tar --sparse -C "$STAGE" -czf "$OUT" "$(basename "$ROOT")"
(
  cd "$(dirname "$OUT")"
  sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256"
)
tar -tzf "$OUT" >/dev/null
printf 'Created: %s\n' "$OUT"
printf 'SHA-256: '; cut -d' ' -f1 "$OUT.sha256"
printf 'Bytes: '; stat -c '%s' "$OUT"
