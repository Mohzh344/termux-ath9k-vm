#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v pkg >/dev/null 2>&1 || { echo 'Run this installer inside Termux.' >&2; exit 1; }
# shellcheck source=../src/vm-storage-lib.sh
. "$BASE_DIR/src/vm-storage-lib.sh"

printf 'Installing host dependencies for the combined Full + Lite bundle...\n'
pkg update -y
pkg install -y qemu-system-aarch64-headless termux-api socat e2fsprogs
find "$BASE_DIR/bin" "$BASE_DIR/full/bin" "$BASE_DIR/lite/bin" -type f -name '*.sh' -exec chmod +x {} +

VM_STATE_ROOT="${VM_STATE_ROOT:-$(vm_default_state_root)}"
export VM_STATE_ROOT
LEGACY_DIR="${VM_LEGACY_DIR:-}"
SOURCE_FULL_DIR="$BASE_DIR/full"
SOURCE_LITE_DIR="$BASE_DIR/lite"
if [ -n "$LEGACY_DIR" ]; then
  SOURCE_FULL_DIR="$LEGACY_DIR/full"
  SOURCE_LITE_DIR="$LEGACY_DIR/lite"
  [ -d "$LEGACY_DIR" ] || { echo "VM_LEGACY_DIR does not exist: $LEGACY_DIR" >&2; exit 1; }
  printf 'Adopting images from legacy checkout: %s\n' "$LEGACY_DIR"
fi
vm_storage_init "$BASE_DIR" "$SOURCE_FULL_DIR" "$SOURCE_LITE_DIR" >/dev/null
# Once the image is safely adopted, remove only duplicate bundled copies from
# the new archive. The persistent image is never replaced by an update.
vm_cleanup_bundled_image "$BASE_DIR/full/guest/alpine-ath9k.img" "$VM_STATE_ROOT/full/alpine-ath9k.img" Full
vm_cleanup_bundled_image "$BASE_DIR/lite/guest/alpine-ath9k-v030-lite.img" "$VM_STATE_ROOT/lite/alpine-ath9k-v030-lite.img" Lite

printf '\nInstallation complete.\n'
printf 'Persistent VM data: %s\n' "$VM_STATE_ROOT"
printf 'The Full and Lite images are kept outside the release tree, so updating this archive preserves installed packages and files.\n'
printf 'Recommended launcher:\n  %s/bin/vm-launcher.sh\n' "$BASE_DIR"
printf 'Administration:\n  %s/bin/vmctl.sh doctor\n  %s/bin/vmctl.sh info\n  %s/bin/vmctl.sh status\n' "$BASE_DIR" "$BASE_DIR" "$BASE_DIR"
printf 'Backup and migration:\n  %s/bin/vmctl.sh backup --full\n  %s/bin/vmctl.sh export --lite\n  %s/bin/vmctl.sh import --full /path/to/export.tar.gz\n' "$BASE_DIR" "$BASE_DIR" "$BASE_DIR"
printf 'For an existing old checkout, run: VM_LEGACY_DIR=/path/to/old/termux-ath9k-vm bash bin/install-termux.sh\n'
