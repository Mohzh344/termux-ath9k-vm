#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$BASE_DIR/bin/vm-launcher-unified.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/unified-launcher-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mk_full(){
  local d="$1"; mkdir -p "$d/guest" "$d/bin"
  : > "$d/guest/alpine-ath9k.img"
  : > "$d/guest/vmlinuz-lts"
  : > "$d/guest/initramfs-lts"
}
mk_lite(){
  local d="$1"; mkdir -p "$d/guest" "$d/bin"
  : > "$d/guest/alpine-ath9k-v030-lite.img"
  : > "$d/guest/vmlinuz-tiny"
  : > "$d/guest/vmlinuz-safe"
  : > "$d/guest/vmlinuz-lts-lite"
  : > "$d/guest/initramfs-lts-lite"
}
assert_contains(){
  local hay="$1" needle="$2" label="$3"
  grep -Fq "$needle" <<<"$hay" || { echo "FAIL: $label" >&2; echo "$hay" >&2; exit 1; }
  echo "PASS: $label"
}
assert_fails(){
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "FAIL: $label (expected failure)" >&2; exit 1; fi
  echo "PASS: $label"
}

# Single complete Full bundle.
mkdir -p "$TMP/full-only"
mk_full "$TMP/full-only/full"
out="$(VM_STORAGE_ENABLED=0 FULL_DIR="$TMP/full-only/full" LITE_DIR="$TMP/full-only/lite" "$LAUNCHER" --dry-run --non-interactive)"
assert_contains "$out" 'Detected=Full' 'single Full detection'

# Single complete Lite bundle, default safe tier, no QEMU.
mkdir -p "$TMP/lite-only"
mk_lite "$TMP/lite-only/lite"
out="$(VM_STORAGE_ENABLED=0 FULL_DIR="$TMP/lite-only/full" LITE_DIR="$TMP/lite-only/lite" "$LAUNCHER" --dry-run --non-interactive)"
assert_contains "$out" 'Detected=Lite' 'single Lite detection'
assert_contains "$out" 'tier=safe' 'safe is non-interactive default'

# Both complete bundles must fail in non-interactive mode rather than guess.
mkdir -p "$TMP/both"
mk_full "$TMP/both/full"
mk_lite "$TMP/both/lite"
assert_fails 'ambiguous bundles fail non-interactively' env VM_STORAGE_ENABLED=0 FULL_DIR="$TMP/both/full" LITE_DIR="$TMP/both/lite" "$LAUNCHER" --dry-run --non-interactive

# Explicit variant wins when both exist.
out="$(VM_STORAGE_ENABLED=0 FULL_DIR="$TMP/both/full" LITE_DIR="$TMP/both/lite" VM_VARIANT=full "$LAUNCHER" --dry-run --non-interactive)"
assert_contains "$out" 'Detected=Full' 'explicit Full selection'
out="$(VM_STORAGE_ENABLED=0 FULL_DIR="$TMP/both/full" LITE_DIR="$TMP/both/lite" VM_VARIANT=lite KERNEL_TIER=tiny PROFILE=wifi-only "$LAUNCHER" --dry-run --non-interactive)"
assert_contains "$out" 'Detected=Lite' 'explicit Lite selection'
assert_contains "$out" 'tier=tiny' 'explicit Tier is preserved'

# Incomplete bundles fail safely.
mkdir -p "$TMP/incomplete/lite/guest"
: > "$TMP/incomplete/lite/guest/alpine-ath9k-v030-lite.img"
assert_fails 'incomplete Lite bundle fails' env VM_STORAGE_ENABLED=0 FULL_DIR="$TMP/incomplete/full" LITE_DIR="$TMP/incomplete/lite" "$LAUNCHER" --dry-run --non-interactive

echo 'All unified launcher tests passed.'
