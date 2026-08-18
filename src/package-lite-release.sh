#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-v0.3.0-lite}"
case "$VERSION" in v[0-9]*.[0-9]*.[0-9]*-lite) ;; *) echo 'Version must look like vX.Y.Z-lite' >&2; exit 2 ;; esac
pgrep -af '^qemu-system-aarch64' >/dev/null && { echo 'Refusing to package while QEMU is running.' >&2; exit 1; }
for f in README-lite.md LICENSE docs/LITE-v0.3.0.md bin/launch-vm-lite.sh bin/qemu-lite-direct-inner.sh bin/usb-attach-lite-direct.sh src/build-lite-image.sh src/guest-install-wifi-tools.sh guest/alpine-ath9k-v030-lite.img guest/vmlinuz-tiny guest/vmlinuz-safe guest/vmlinuz-lts-lite guest/initramfs-lts-lite; do
  [ -s "$BASE_DIR/$f" ] || { echo "missing required file: $f" >&2; exit 1; }
done
OUT="$BASE_DIR/dist"
STAGE="$(mktemp -d "$BASE_DIR/.lite-release-stage.XXXXXX")"
cleanup(){ rm -rf -- "$STAGE"; }
trap cleanup EXIT INT TERM
ROOT="$STAGE/termux-ath9k-vm-lite"
mkdir -p "$ROOT/guest" "$ROOT/bin" "$ROOT/src" "$ROOT/docs"
cp -p "$BASE_DIR/README-lite.md" "$ROOT/README.md"
cp -p "$BASE_DIR/LICENSE" "$ROOT/"
cp -p "$BASE_DIR/docs/LITE-v0.3.0.md" "$ROOT/docs/"
cp -p "$BASE_DIR/bin/launch-vm-lite.sh" "$BASE_DIR/bin/qemu-lite-direct-inner.sh" "$BASE_DIR/bin/usb-attach-lite-direct.sh" "$ROOT/bin/"
cp -p "$BASE_DIR/src/build-lite-image.sh" "$BASE_DIR/src/guest-install-wifi-tools.sh" "$BASE_DIR/src/package-lite-release.sh" "$ROOT/src/"
cp --sparse=always -p "$BASE_DIR/guest/alpine-ath9k-v030-lite.img" "$ROOT/guest/"
cp -p "$BASE_DIR/guest/vmlinuz-tiny" "$BASE_DIR/guest/vmlinuz-safe" "$BASE_DIR/guest/vmlinuz-lts-lite" "$BASE_DIR/guest/initramfs-lts-lite" "$ROOT/guest/"
(
  cd "$ROOT/guest"
  sha256sum alpine-ath9k-v030-lite.img vmlinuz-tiny vmlinuz-safe vmlinuz-lts-lite initramfs-lts-lite > SHA256SUMS
)
mkdir -p "$OUT"
ARCHIVE="$OUT/termux-ath9k-vm-lite-ready.tar.gz"
SUM="$ARCHIVE.sha256"
rm -f -- "$ARCHIVE" "$SUM"
tar --sparse -czf "$ARCHIVE" -C "$STAGE" termux-ath9k-vm-lite
sha256sum "$ARCHIVE" > "$SUM"
tar -tzf "$ARCHIVE" >/dev/null
printf 'Lite package created and verified:\n  %s\n  %s\n' "$ARCHIVE" "$SUM"
