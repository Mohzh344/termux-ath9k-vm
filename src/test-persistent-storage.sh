#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FULL_SOURCE="${FULL_SOURCE:-$(find /tmp /home/ubuntu -type f -path '*/guest/alpine-ath9k.img' -print -quit 2>/dev/null || true)}"
LITE_SOURCE="${LITE_SOURCE:-$BASE_DIR/guest/alpine-ath9k-v030-lite.img}"
FULL_KERNEL_SOURCE="${FULL_KERNEL_SOURCE:-$(dirname "$FULL_SOURCE")/vmlinuz-lts}"
FULL_INITRD_SOURCE="${FULL_INITRD_SOURCE:-$(dirname "$FULL_SOURCE")/initramfs-lts}"
[ -f "$FULL_SOURCE" ] && [ -f "$LITE_SOURCE" ] || { echo 'Full/Lite source images are required.' >&2; exit 1; }
[ -f "$FULL_KERNEL_SOURCE" ] && [ -f "$FULL_INITRD_SOURCE" ] || { echo 'Full kernel/initramfs are required.' >&2; exit 1; }

T="$(mktemp -d /tmp/persistent-storage-test.XXXXXX)"
trap 'rm -rf "$T"' EXIT
source "$BASE_DIR/src/vm-storage-lib.sh"

make_bundle() {
  local root="$1"
  mkdir -p "$root/full/guest" "$root/lite/guest"
  cp --sparse=always --reflink=auto "$FULL_SOURCE" "$root/full/guest/alpine-ath9k.img"
  cp -p "$FULL_KERNEL_SOURCE" "$root/full/guest/vmlinuz-lts"
  cp -p "$FULL_INITRD_SOURCE" "$root/full/guest/initramfs-lts"
  cp --sparse=always --reflink=auto "$LITE_SOURCE" "$root/lite/guest/alpine-ath9k-v030-lite.img"
  cp -p "$BASE_DIR/guest/vmlinuz-tiny" "$root/lite/guest/vmlinuz-tiny"
  cp -p "$BASE_DIR/guest/vmlinuz-safe" "$root/lite/guest/vmlinuz-safe"
  cp -p "$BASE_DIR/guest/vmlinuz-lts-lite" "$root/lite/guest/vmlinuz-lts-lite"
  cp -p "$BASE_DIR/guest/initramfs-lts-lite" "$root/lite/guest/initramfs-lts-lite"
}

make_bundle "$T/release-one"
VM_STATE_ROOT="$T/state" FULL_DIR="$T/release-one/full" LITE_DIR="$T/release-one/lite" \
  "$BASE_DIR/bin/vm-launcher.sh" --lite --dry-run --non-interactive >"$T/lite-first.txt"
lite_image="$T/state/lite/alpine-ath9k-v030-lite.img"
[ -f "$lite_image" ]
[ ! -e "$T/release-one/lite/guest/alpine-ath9k-v030-lite.img" ]

printf 'persistent-data\n' > "$T/persistent-data"
vm_guest_write_file "$lite_image" "$T/persistent-data" /root/persistent-data.txt 0100600

# A later archive has a different bundled image, but must not replace state.
make_bundle "$T/release-two"
printf 'new-archive-data\n' > "$T/new-archive-data"
vm_guest_write_file "$T/release-two/lite/guest/alpine-ath9k-v030-lite.img" "$T/new-archive-data" /root/persistent-data.txt 0100600
for tier in tiny safe lts; do
  out="$(VM_STATE_ROOT="$T/state" FULL_DIR="$T/release-two/full" LITE_DIR="$T/release-two/lite" KERNEL_TIER="$tier" \
    "$BASE_DIR/bin/vm-launcher.sh" --lite --dry-run --non-interactive)"
  grep -q "disk=$lite_image" <<<"$out"
done
grep -qx 'persistent-data' <(debugfs -R 'cat /root/persistent-data.txt' "$lite_image" 2>/dev/null)
echo 'PASS: Lite tiny/safe/lts reuse one persistent image and a later archive cannot replace it.'

# Full has an independent persistent image and can be backed up.
VM_STATE_ROOT="$T/state" FULL_DIR="$T/release-one/full" LITE_DIR="$T/release-one/lite" \
  "$BASE_DIR/bin/vm-launcher.sh" --full --dry-run --non-interactive >"$T/full-first.txt"
full_image="$T/state/full/alpine-ath9k.img"
[ -f "$full_image" ]
full_backup="$(VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vm-backup.sh" --full | sed -n 's/^  //p' | head -1)"
lite_backup="$(VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vm-backup.sh" --lite | sed -n 's/^  //p' | head -1)"
[ -f "$full_backup" ] && [ -f "$lite_backup" ]
echo 'PASS: Full and Lite sparse backups are created.'

# The unified administration command must persist PATH, report state, and grow
# a stopped image without losing its contents.
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vmctl.sh" path add --lite /opt/test-tools >/tmp/vmctl-path-add.out
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vmctl.sh" path list --lite | grep -qx '/opt/test-tools'
debugfs -R 'cat /etc/profile.d/vmctl-path.sh' "$lite_image" 2>/dev/null | grep -q 'vmctl-path: /opt/test-tools'
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vmctl.sh" info --lite >"$T/vmctl-info.txt"
grep -q 'managed_path_entries=' "$T/vmctl-info.txt"
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vmctl.sh" status >"$T/vmctl-status.txt"
grep -q "VM_STATE_ROOT=$T/state" "$T/vmctl-status.txt"
VM_STATE_ROOT="$T/state" FULL_DIR="$T/release-one/full" LITE_DIR="$T/release-one/lite" \
  "$BASE_DIR/bin/vmctl.sh" doctor --lite >"$T/vmctl-doctor.txt" || true
grep -q '\[PASS\].*lite image' "$T/vmctl-doctor.txt"
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vmctl.sh" usb >"$T/vmctl-usb.txt"
grep -q 'USB' "$T/vmctl-usb.txt"
old_size="$(stat -c '%s' "$lite_image")"
new_size=$((old_size + 4194304))
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vmctl.sh" resize --lite "$new_size" >"$T/vmctl-resize.txt"
grep -q 'Image grown successfully' "$T/vmctl-resize.txt"
[ "$(stat -c '%s' "$lite_image")" -eq "$new_size" ]
e2fsck -fn "$lite_image" >/dev/null
echo 'PASS: vmctl Lite path, info, status, doctor, USB diagnostics, and resize work.'

VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vmctl.sh" path add --full /opt/full-tools >/dev/null
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vmctl.sh" path list --full | grep -qx '/opt/full-tools'
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vmctl.sh" info --full >"$T/vmctl-full-info.txt"
grep -q 'managed_path_entries=' "$T/vmctl-full-info.txt"
VM_STATE_ROOT="$T/state" FULL_DIR="$T/release-one/full" LITE_DIR="$T/release-one/lite" \
  "$BASE_DIR/bin/vmctl.sh" doctor --full >"$T/vmctl-full-doctor.txt" || true
grep -q '\[PASS\].*full image' "$T/vmctl-full-doctor.txt"
old_full_size="$(stat -c '%s' "$full_image")"
new_full_size=$((old_full_size + 4194304))
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vmctl.sh" resize --full "$new_full_size" >"$T/vmctl-full-resize.txt"
grep -q 'Image grown successfully' "$T/vmctl-full-resize.txt"
[ "$(stat -c '%s' "$full_image")" -eq "$new_full_size" ]
e2fsck -fn "$full_image" >/dev/null

held_lock="$(VM_STATE_ROOT="$T/state" vm_lock_image "$lite_image")"
if VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vmctl.sh" path add --lite /opt/blocked-by-lock >/dev/null 2>&1; then
  echo 'lock test unexpectedly succeeded' >&2
  exit 1
fi
VM_STATE_ROOT="$T/state" vm_unlock_image "$lite_image"
echo 'PASS: vmctl Full path, info, doctor, resize, and active-lock rejection work.'

export_file="$T/lite-export.tar.gz"
full_export_file="$T/full-export.tar.gz"
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vm-export.sh" --lite --output "$export_file" >/dev/null
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vm-export.sh" --full --output "$full_export_file" >/dev/null
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vm-import.sh" --full "$export_file" >/dev/null
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vm-import.sh" --lite "$full_export_file" >/dev/null
grep -qx 'persistent-data' <(debugfs -R 'cat /root/persistent-data.txt' "$full_image" 2>/dev/null)
e2fsck -fn "$lite_image" >/dev/null
e2fsck -fn "$full_image" >/dev/null
echo 'PASS: Lite-to-Full export/import preserves user data and both images remain valid.'
