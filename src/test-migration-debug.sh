#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FULL_SOURCE="${FULL_SOURCE:-$(find /tmp /home/ubuntu -type f -path '*/guest/alpine-ath9k.img' -print -quit 2>/dev/null || true)}"
[ -f "$FULL_SOURCE" ] || { echo "set FULL_SOURCE to a Full guest image" >&2; exit 1; }
T="$(mktemp -d /tmp/migration-test-debug.XXXXXX)"
trap 'rc=$?; echo "TEST_TEMP=$T"; echo "TEST_RC=$rc"; if [ "$rc" -ne 0 ]; then find "$T" -maxdepth 3 -type f -printf "%p\n" 2>/dev/null; for f in "$T"/*.err; do [ -f "$f" ] && { echo "--- $f"; cat "$f"; }; done; else rm -rf "$T"; fi; exit "$rc"' EXIT
mkdir -p "$T/bundle/full/guest" "$T/bundle/lite/guest" "$T/state"
cp --sparse=always --reflink=auto "$FULL_SOURCE" "$T/bundle/full/guest/alpine-ath9k.img"
cp --sparse=always --reflink=auto "$BASE_DIR/guest/alpine-ath9k-v030-lite.img" "$T/bundle/lite/guest/alpine-ath9k-v030-lite.img"
for f in vmlinuz-lts vmlinuz-tiny vmlinuz-safe vmlinuz-lts-lite initramfs-lts-lite; do : > "$T/bundle/lite/guest/$f"; done
: > "$T/bundle/full/guest/vmlinuz-lts"
: > "$T/bundle/full/guest/initramfs-lts"
VM_STATE_ROOT="$T/state" VM_STORAGE_ENABLED=1 FULL_DIR="$T/bundle/full" LITE_DIR="$T/bundle/lite" "$BASE_DIR/bin/vm-launcher.sh" --lite --dry-run --non-interactive >"$T/lite-run.txt" 2>"$T/lite-run.err"
test -f "$T/state/lite/alpine-ath9k-v030-lite.img"
test ! -e "$T/bundle/lite/guest/alpine-ath9k-v030-lite.img"
source "$BASE_DIR/src/vm-storage-lib.sh"
printf 'sentinel-from-lite\n' >"$T/sentinel file"
vm_guest_write_file "$T/state/lite/alpine-ath9k-v030-lite.img" "$T/sentinel file" '/root/migration-sentinel.txt' 0100600
printf 'exported-tool\n' >"$T/path file"
vm_guest_write_file "$T/state/lite/alpine-ath9k-v030-lite.img" "$T/path file" '/etc/profile.d/migration-tool.sh' 0100644
debugfs -R "dump /etc/apk/world $T/world" "$T/state/lite/alpine-ath9k-v030-lite.img" >/dev/null
printf 'wireless-tools\n' >>"$T/world"
vm_guest_write_file "$T/state/lite/alpine-ath9k-v030-lite.img" "$T/world" '/etc/apk/world' 0100644
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vm-export.sh" --lite --output "$T/lite-export.tar.gz" >"$T/export.txt" 2>"$T/export.err"
VM_STATE_ROOT="$T/state" VM_STORAGE_ENABLED=1 FULL_DIR="$T/bundle/full" LITE_DIR="$T/bundle/lite" "$BASE_DIR/bin/vm-launcher.sh" --full --dry-run --non-interactive >"$T/full-run.txt" 2>"$T/full-run.err"
VM_STATE_ROOT="$T/state" "$BASE_DIR/bin/vm-import.sh" --full "$T/lite-export.tar.gz" >"$T/import.txt" 2>"$T/import.err"
debugfs -R 'cat /root/migration-sentinel.txt' "$T/state/full/alpine-ath9k.img" 2>/dev/null | grep -qx 'sentinel-from-lite'
debugfs -R 'cat /etc/profile.d/migration-tool.sh' "$T/state/full/alpine-ath9k.img" 2>/dev/null | grep -qx 'exported-tool'
debugfs -R 'cat /root/.vm-migration/apk-world' "$T/state/full/alpine-ath9k.img" 2>/dev/null | grep -q 'wireless-tools'
debugfs -R 'cat /root/.vm-migration/apply-packages.sh' "$T/state/full/alpine-ath9k.img" 2>/dev/null | grep -q 'apk add --no-cache'
e2fsck -fn "$T/state/lite/alpine-ath9k-v030-lite.img" >/dev/null
e2fsck -fn "$T/state/full/alpine-ath9k.img" >/dev/null
echo 'MIGRATION TEST: PASS'
echo '--- lite launcher ---'; cat "$T/lite-run.txt"
echo '--- full launcher ---'; cat "$T/full-run.txt"
echo '--- export ---'; cat "$T/export.txt"
echo '--- import ---'; cat "$T/import.txt"
