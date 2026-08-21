#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d /tmp/image-write-test.XXXXXX)"
trap 'rm -rf "$T"' EXIT
source "$BASE_DIR/src/vm-storage-lib.sh"
cp --sparse=always --reflink=auto "$BASE_DIR/guest/alpine-ath9k-v030-lite.img" "$T/test.img"
check() {
  echo "--- $1"
  e2fsck -fn "$T/test.img" 2>&1 | tail -20
  rc=${PIPESTATUS[0]}
  echo "e2fsck_rc=$rc"
  [ "$rc" -eq 0 ]
}
check original
printf 'sentinel\n' > "$T/sentinel"
vm_guest_write_file "$T/test.img" "$T/sentinel" /root/sentinel.txt 0100600
check sentinel
printf 'path\n' > "$T/path"
vm_guest_write_file "$T/test.img" "$T/path" /etc/profile.d/test-path.sh 0100644
check profile
# Use a copy of world and replace it, as the migration test does.
debugfs -R "dump /etc/apk/world $T/world" "$T/test.img" >/dev/null
printf 'wireless-tools\n' >> "$T/world"
vm_guest_write_file "$T/test.img" "$T/world" /etc/apk/world 0100644
echo '--- etc after world'; debugfs -R 'ls -l /etc' "$T/test.img" 2>&1 | tail -60
echo '--- apk after world'; debugfs -R 'ls -l /etc/apk' "$T/test.img" 2>&1 | tail -30
check world
