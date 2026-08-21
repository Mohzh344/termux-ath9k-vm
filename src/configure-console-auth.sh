#!/usr/bin/env bash
# Configure the stopped Alpine guest's ttyAMA0 authentication mode.
# root-console is the default direct root shell. login uses BusyBox getty and
# the existing root password. login-empty intentionally clears root's password
# and is for a local test console only.
set -euo pipefail

IMAGE="${1:-}"
MODE="${2:-root-console}"
[ -n "$IMAGE" ] || { echo "usage: $0 /path/to/guest.img [root-console|login|login-empty]" >&2; exit 2; }
[ -f "$IMAGE" ] || { echo "missing guest image: $IMAGE" >&2; exit 1; }
case "$MODE" in
  root-console|login|login-empty) ;;
  *) echo 'AUTH_MODE must be root-console, login, or login-empty' >&2; exit 2 ;;
esac
command -v debugfs >/dev/null 2>&1 || { echo 'missing debugfs; install e2fsprogs' >&2; exit 1; }
command -v e2fsck >/dev/null 2>&1 || { echo 'missing e2fsck; install e2fsprogs' >&2; exit 1; }
if ps -eo args= | grep -F 'qemu-system-aarch64' | grep -F -- "$IMAGE" | grep -vF -- 'grep -F' >/dev/null 2>&1; then
  echo 'refusing to edit this image while its QEMU process is running' >&2
  exit 1
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
STORAGE_LIB="$SCRIPT_DIR/vm-storage-lib.sh"
[ -r "$STORAGE_LIB" ] || STORAGE_LIB="$SCRIPT_DIR/../../src/vm-storage-lib.sh"
if [ -r "$STORAGE_LIB" ]; then
  # shellcheck source=vm-storage-lib.sh
  . "$STORAGE_LIB"
fi
if [ "${CREATE_BACKUP:-1}" != 0 ]; then
  if command -v vm_backup_image >/dev/null 2>&1; then
    BACKUP_DIR="${BACKUP_DIR:-$(vm_default_state_root)/backups}"
    AUTH_BACKUP="$(vm_backup_image "$IMAGE" before-auth "$BACKUP_DIR")"
    printf 'Created auth-change backup: %s\n' "$AUTH_BACKUP"
  else
    printf 'WARNING: storage helper unavailable; auth change continues without automatic backup.\n' >&2
  fi
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/console-auth.XXXXXX")"
cleanup(){ rm -rf -- "$WORK"; }
trap cleanup EXIT INT TERM

INI="$WORK/inittab"
PASSWD="$WORK/passwd"
SHADOW="$WORK/shadow"
case "$MODE" in
  root-console) ENTRY='ttyAMA0::respawn:/bin/sh -l' ;;
  login|login-empty) ENTRY='ttyAMA0::respawn:/sbin/getty -L 0 ttyAMA0 vt100' ;;
esac

debugfs -R "dump /etc/inittab $INI" "$IMAGE" >/dev/null
if grep -q '^ttyAMA0:' "$INI"; then
  sed -E -i "s|^ttyAMA0:.*$|$ENTRY|" "$INI"
else
  printf '\n%s\n' "$ENTRY" >> "$INI"
fi
grep -qxF "$ENTRY" "$INI" || { echo 'failed to prepare ttyAMA0 auth entry' >&2; exit 1; }

write_guest_file(){
  local local_file="$1" guest_file="$2" mode="$3"
  if command -v vm_guest_write_file >/dev/null 2>&1; then
    vm_guest_write_file "$IMAGE" "$local_file" "$guest_file" "$mode"
  else
    debugfs -w -R "rm $guest_file" "$IMAGE" >/dev/null 2>&1 || true
    debugfs -w -R "write $local_file $guest_file" "$IMAGE" >/dev/null
    debugfs -w -R "set_inode_field $guest_file uid 0" "$IMAGE" >/dev/null
    debugfs -w -R "set_inode_field $guest_file gid 0" "$IMAGE" >/dev/null
    debugfs -w -R "set_inode_field $guest_file mode $mode" "$IMAGE" >/dev/null
  fi
}

write_guest_file "$INI" /etc/inittab 0100644

# Normalize the root shadow record to the standard nine-field format. The
# historical images used short records such as root::1:::::, which makes
# BusyBox passwd fall back to /etc/passwd and then causes a later login to
# reject the newly written password.
debugfs -R "dump /etc/passwd $PASSWD" "$IMAGE" >/dev/null
debugfs -R "dump /etc/shadow $SHADOW" "$IMAGE" >/dev/null
grep -q '^root:' "$PASSWD" || { echo 'root account is missing from /etc/passwd' >&2; exit 1; }
grep -q '^root:' "$SHADOW" || { echo 'root account is missing from /etc/shadow' >&2; exit 1; }
if [ "$MODE" = login-empty ]; then
  sed -E -i 's|^root:[^:]*:|root::|' "$PASSWD"
  sed -E -i 's|^root:[^:]*:|root::|' "$SHADOW"
fi
awk -F: -v OFS=: '
  $1 == "root" {
    print $1, $2, ($3=="" ? "0" : $3), ($4=="" ? "0" : $4), ($5=="" ? "99999" : $5), ($6=="" ? "7" : $6), $7, $8, $9
    next
  }
  { print }
' "$SHADOW" > "$SHADOW.normalized"
mv "$SHADOW.normalized" "$SHADOW"
write_guest_file "$PASSWD" /etc/passwd 0100644
write_guest_file "$SHADOW" /etc/shadow 0100600

# Confirm the image remains structurally clean after debugfs writes.
e2fsck -fn "$IMAGE" >/dev/null
actual_ini="$(debugfs -R 'cat /etc/inittab' "$IMAGE" 2>/dev/null)"
printf '%s\n' "$actual_ini" | grep -qxF "$ENTRY"
if [ "$MODE" = login-empty ]; then
  actual_passwd="$(debugfs -R 'cat /etc/passwd' "$IMAGE" 2>/dev/null)"
  actual_shadow="$(debugfs -R 'cat /etc/shadow' "$IMAGE" 2>/dev/null)"
  printf '%s\n' "$actual_passwd" | grep -q '^root::'
  printf '%s\n' "$actual_shadow" | grep -q '^root::'
fi

case "$MODE" in
  root-console) echo 'AUTH_MODE=root-console: direct root shell; no username/password prompt.' ;;
  login) echo 'AUTH_MODE=login: getty/login prompt; existing root password is preserved.' ;;
  login-empty) echo 'AUTH_MODE=login-empty: getty/login prompt with an intentionally empty root password; local testing only.' ;;
esac
