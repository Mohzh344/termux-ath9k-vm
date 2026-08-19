#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-v0.3.1}"
DIST_DIR="${DIST_DIR:-$BASE_DIR/dist}"
FULL_ARCHIVE="${FULL_ARCHIVE:-$BASE_DIR/../termux-ath9k-vm-release-work/termux-ath9k-vm-ready.tar.gz}"
OLD_UNIFIED_ARCHIVE="${OLD_UNIFIED_ARCHIVE:-$BASE_DIR/dist/termux-ath9k-vm-full-lite-ready.tar.gz}"
LITE_BUILD_DIR="${LITE_BUILD_DIR:-$BASE_DIR/../termux-ath9k-vm-v031-lite-build/guest}"
KERNEL_DIR="${KERNEL_DIR:-$BASE_DIR/../termux-ath9k-vm-v031-guest}"
OUT="${OUT:-$DIST_DIR/termux-ath9k-vm-full-lite-ready.tar.gz}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/termux-ath9k-v031-unified.XXXXXX")"
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
  [ -s "$f" ] || die "v0.3.1 Lite artifact not found: $f"
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

# Replace only Lite guest artifacts. Keep the historical internal image name
# for launcher compatibility while using the newly rebuilt v0.3.1 contents.
rm -f "$ROOT/lite/guest/alpine-ath9k-v030-lite.img" "$ROOT/lite/guest/vmlinuz-tiny" "$ROOT/lite/guest/vmlinuz-safe" "$ROOT/lite/guest/vmlinuz-lts-lite" "$ROOT/lite/guest/initramfs-lts-lite"
cp --sparse=always "$LITE_BUILD_DIR/alpine-ath9k-v031-lite.img" "$ROOT/lite/guest/alpine-ath9k-v030-lite.img"
cp -p "$KERNEL_DIR/vmlinuz-tiny" "$KERNEL_DIR/vmlinuz-safe" "$LITE_BUILD_DIR/vmlinuz-lts-lite" "$LITE_BUILD_DIR/initramfs-lts-lite" "$ROOT/lite/guest/"

# Use v0.3.1 Lite scripts and documentation. Full nested files are untouched.
cp -p "$BASE_DIR/README-lite-v0.3.1.md" "$ROOT/lite/README.md"
cp -p "$BASE_DIR/README-UNIFIED.md" "$ROOT/README.md"
cp -p "$BASE_DIR/bin/vm-launcher-unified.sh" "$ROOT/bin/vm-launcher.sh"
cp -p "$BASE_DIR/bin/vm-launcher-unified.sh" "$ROOT/bin/vm-launcher-unified.sh"
cp -p "$BASE_DIR/src/install-termux-unified.sh" "$ROOT/bin/install-termux.sh"
cp -p "$BASE_DIR/bin/launch-vm-lite.sh" "$BASE_DIR/bin/qemu-lite-direct-inner.sh" "$BASE_DIR/bin/usb-attach-lite-direct.sh" "$ROOT/lite/bin/"
cp -p "$BASE_DIR/src/build-lite-image.sh" "$BASE_DIR/src/guest-install-wifi-tools.sh" "$BASE_DIR/src/package-lite-release.sh" "$BASE_DIR/src/build-kernel-tiers.sh" "$BASE_DIR/src/verify-kernel-tiers.sh" "$ROOT/lite/src/"
cp -p "$BASE_DIR/docs/LITE-v0.3.1.md" "$BASE_DIR/docs/RELEASE-v0.3.1.md" "$BASE_DIR/docs/UNIFIED-RELEASE.md" "$ROOT/docs/"
chmod +x "$ROOT/bin/"*.sh "$ROOT/lite/bin/"*.sh "$ROOT/lite/src/"*.sh

(
  cd "$ROOT/lite/guest"
  sha256sum alpine-ath9k-v030-lite.img vmlinuz-tiny vmlinuz-safe vmlinuz-lts-lite initramfs-lts-lite > SHA256SUMS
)
(
  cd "$ROOT/lite/guest"
  sha256sum alpine-ath9k-v030-lite.img vmlinuz-tiny vmlinuz-safe vmlinuz-lts-lite initramfs-lts-lite > SHA256SUMS-v0.3.1-lite
)

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
