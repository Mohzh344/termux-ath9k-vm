#!/usr/bin/env bash
# Build one downloadable archive containing the canonical Full and Lite bundles.
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-v0.3.0-unified}"
DIST_DIR="${DIST_DIR:-$BASE_DIR/dist}"
FULL_ARCHIVE="${FULL_ARCHIVE:-$BASE_DIR/../termux-ath9k-vm-release-work/termux-ath9k-vm-ready.tar.gz}"
LITE_ARCHIVE="${LITE_ARCHIVE:-$BASE_DIR/../termux-ath9k-vm-release-work/termux-ath9k-vm-lite-ready.tar.gz}"
OUT="${OUT:-$DIST_DIR/termux-ath9k-vm-full-lite-ready.tar.gz}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/termux-ath9k-vm-unified.XXXXXX")"
ROOT="$STAGE/termux-ath9k-vm-full-lite"
cleanup(){ rm -rf "$STAGE"; }
trap cleanup EXIT

die(){ echo "ERROR: $*" >&2; exit 1; }
for f in "$FULL_ARCHIVE" "$LITE_ARCHIVE"; do [ -f "$f" ] || die "Archive not found: $f"; done
mkdir -p "$ROOT/full" "$ROOT/lite" "$ROOT/bin" "$ROOT/docs" "$DIST_DIR"
tar -xzf "$FULL_ARCHIVE" -C "$ROOT/full" --strip-components=1
tar -xzf "$LITE_ARCHIVE" -C "$ROOT/lite" --strip-components=1

for f in "$ROOT/full/guest/alpine-ath9k.img" "$ROOT/full/guest/vmlinuz-lts" "$ROOT/full/guest/initramfs-lts"; do [ -f "$f" ] || die "Full archive is incomplete: $f"; done
for f in "$ROOT/lite/guest/alpine-ath9k-v030-lite.img" "$ROOT/lite/guest/vmlinuz-tiny" "$ROOT/lite/guest/vmlinuz-safe" "$ROOT/lite/guest/vmlinuz-lts-lite" "$ROOT/lite/guest/initramfs-lts-lite"; do [ -f "$f" ] || die "Lite archive is incomplete: $f"; done

cp "$BASE_DIR/bin/vm-launcher-unified.sh" "$ROOT/bin/vm-launcher.sh"
cp "$BASE_DIR/bin/vm-launcher-unified.sh" "$ROOT/bin/vm-launcher-unified.sh"
cp "$BASE_DIR/src/install-termux-unified.sh" "$ROOT/bin/install-termux.sh"
cp "$BASE_DIR/docs/UNIFIED-RELEASE.md" "$ROOT/docs/UNIFIED-RELEASE.md"
cp "$BASE_DIR/LICENSE" "$ROOT/LICENSE"
chmod +x "$ROOT/bin/"*.sh "$ROOT/full/bin/"*.sh "$ROOT/lite/bin/"*.sh

# The top-level README deliberately describes the combined layout; the nested
# Full README and Lite README remain untouched canonical documentation.
cp "$BASE_DIR/README-UNIFIED.md" "$ROOT/README.md"
sha256sum "$ROOT/full/guest/alpine-ath9k.img" "$ROOT/full/guest/vmlinuz-lts" "$ROOT/full/guest/initramfs-lts" > "$ROOT/full/guest/SHA256SUMS-unified-check"
sha256sum "$ROOT/lite/guest/alpine-ath9k-v030-lite.img" "$ROOT/lite/guest/vmlinuz-tiny" "$ROOT/lite/guest/vmlinuz-safe" "$ROOT/lite/guest/vmlinuz-lts-lite" "$ROOT/lite/guest/initramfs-lts-lite" > "$ROOT/lite/guest/SHA256SUMS-unified-check"

rm -f "$OUT" "$OUT.sha256"
tar -C "$STAGE" -czf "$OUT" "$(basename "$ROOT")"
sha256sum "$OUT" > "$OUT.sha256"
printf 'Created: %s\n' "$OUT"
printf 'SHA-256: '; cut -d' ' -f1 "$OUT.sha256"
printf 'Bytes: '; stat -c '%s' "$OUT"
