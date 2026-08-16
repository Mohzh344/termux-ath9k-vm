#!/data/data/com.termux/files/usr/bin/bash
# Build a distributable, sparse-aware release archive from a stopped VM image.
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "Usage: $0 vX.Y.Z" >&2; exit 2; }
case "$VERSION" in v[0-9]*.[0-9]*.[0-9]*) ;; *) echo 'Version must look like vX.Y.Z' >&2; exit 2;; esac
pgrep -af '^qemu-system-aarch64' >/dev/null && { echo 'Refusing to package a running VM image. Shut down QEMU cleanly first.' >&2; exit 1; }
for f in README.md LICENSE guest/alpine-ath9k.img guest/vmlinuz-lts guest/initramfs-lts; do [ -s "$BASE_DIR/$f" ] || { echo "missing required file: $f" >&2; exit 1; }; done
OUT="$BASE_DIR/dist"
STAGE="$(mktemp -d "$BASE_DIR/.release-stage.XXXXXX")"
cleanup(){ rm -rf -- "$STAGE"; }
trap cleanup EXIT INT TERM
ROOT="$STAGE/termux-ath9k-vm"
mkdir -p "$ROOT"
cp -p "$BASE_DIR/README.md" "$BASE_DIR/LICENSE" "$ROOT/"
[ ! -f "$BASE_DIR/.gitignore" ] || cp -p "$BASE_DIR/.gitignore" "$ROOT/"
cp -a "$BASE_DIR/bin" "$BASE_DIR/docs" "$BASE_DIR/src" "$ROOT/"
mkdir -p "$ROOT/guest"
cp --sparse=always -p "$BASE_DIR/guest/alpine-ath9k.img" "$ROOT/guest/"
cp -p "$BASE_DIR/guest/vmlinuz-lts" "$BASE_DIR/guest/initramfs-lts" "$ROOT/guest/"
(
  cd "$ROOT/guest"
  sha256sum alpine-ath9k.img vmlinuz-lts initramfs-lts > SHA256SUMS
)
mkdir -p "$OUT"
ARCHIVE="$OUT/termux-ath9k-vm-ready.tar.gz"
SUM="$ARCHIVE.sha256"
rm -f -- "$ARCHIVE" "$SUM"
tar --sparse -czf "$ARCHIVE" -C "$STAGE" termux-ath9k-vm
sha256sum "$ARCHIVE" > "$SUM"
tar -tzf "$ARCHIVE" >/dev/null
printf 'Release package created and verified:\n  %s\n  %s\n' "$ARCHIVE" "$SUM"
