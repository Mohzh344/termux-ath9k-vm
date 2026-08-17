#!/data/data/com.termux/files/usr/bin/bash
# Offline emergency console recovery: bypass BusyBox login on ttyAMA0.
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DISK="${1:-$BASE_DIR/guest/alpine-ath9k.img}"
command -v debugfs >/dev/null || { echo 'Install e2fsprogs first: pkg install e2fsprogs' >&2; exit 1; }
[ -f "$DISK" ] || { echo "missing disk: $DISK" >&2; exit 1; }
pgrep -af '^qemu-system-aarch64' >/dev/null && { echo 'Refusing to edit a running image.' >&2; exit 1; }
mkdir -p "$BASE_DIR/run"
TMP_INI="$(mktemp "$BASE_DIR/run/inittab.XXXXXX")"
TMP_PW="$(mktemp "$BASE_DIR/run/passwd.XXXXXX")"
cleanup(){ rm -f -- "$TMP_INI" "$TMP_PW"; }
trap cleanup EXIT INT TERM
debugfs -R "dump -p /etc/inittab $TMP_INI" "$DISK" >/dev/null
debugfs -R "dump -p /etc/passwd $TMP_PW" "$DISK" >/dev/null
# SysV/BusyBox init opens ttyAMA0 for this respawn action. /bin/sh therefore
# runs as UID 0 directly on the QEMU serial console; no login/password path remains.
sed -i 's|^ttyAMA0::.*$|ttyAMA0::respawn:/bin/sh|' "$TMP_INI"
sed -i 's/^root:[^:]*:/root::/' "$TMP_PW"
grep -qxF 'ttyAMA0::respawn:/bin/sh' "$TMP_INI" || { echo 'failed to prepare inittab' >&2; exit 1; }
grep -q '^root::0:0:' "$TMP_PW" || { echo 'failed to prepare passwd' >&2; exit 1; }
BACKUP="$(dirname "$DISK")/$(basename "$DISK").before-autologin-$(date +%Y%m%d-%H%M%S).bak"
echo "Creating sparse backup: $BACKUP"
cp --sparse=always "$DISK" "$BACKUP"
for item in '/etc/inittab' '/etc/passwd'; do debugfs -w -R "unlink $item" "$DISK" >/dev/null; done
debugfs -w -R "write $TMP_INI /etc/inittab" "$DISK" >/dev/null
debugfs -w -R "write $TMP_PW /etc/passwd" "$DISK" >/dev/null
for item in '/etc/inittab' '/etc/passwd'; do
  debugfs -w -R "set_inode_field $item uid 0" "$DISK" >/dev/null
  debugfs -w -R "set_inode_field $item gid 0" "$DISK" >/dev/null
  debugfs -w -R "set_inode_field $item mode 0100644" "$DISK" >/dev/null
done
got_ini="$(debugfs -R 'cat /etc/inittab' "$DISK" 2>/dev/null)"
got_pw="$(debugfs -R 'cat /etc/passwd' "$DISK" 2>/dev/null)"
printf '%s\n' "$got_ini" | grep -qxF 'ttyAMA0::respawn:/bin/sh'
printf '%s\n' "$got_pw" | grep -q '^root::0:0:root:/root:/bin/sh$'
echo 'Autologin recovery applied and verified. Boot normally: ttyAMA0 opens a root shell without login or password.'
