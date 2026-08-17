#!/data/data/com.termux/files/usr/bin/bash
# Offline recovery for the initial local-only root login on the guest image.
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DISK="${1:-$BASE_DIR/guest/alpine-ath9k.img}"
command -v debugfs >/dev/null || { echo 'Install e2fsprogs first: pkg install e2fsprogs' >&2; exit 1; }
[ -f "$DISK" ] || { echo "missing disk: $DISK" >&2; exit 1; }
if pgrep -af '^qemu-system-aarch64' >/dev/null; then
  echo 'Refusing to edit a running image. Shut down the VM cleanly first.' >&2
  exit 1
fi
TMP="$(mktemp "$BASE_DIR/run/passwd.XXXXXX")"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT INT TERM
mkdir -p "$BASE_DIR/run"
debugfs -R "dump -p /etc/passwd $TMP" "$DISK" >/dev/null
# Empty root's passwd field intentionally permits the documented first local login.
# It also works when BusyBox falls back from shadow to passwd authentication.
sed -i 's/^root:[^:]*:/root::/' "$TMP"
grep -q '^root::0:0:' "$TMP" || { echo 'failed to prepare root passwd entry' >&2; exit 1; }
BACKUP="$(dirname "$DISK")/$(basename "$DISK").before-root-login-$(date +%Y%m%d-%H%M%S).bak"
echo "Creating sparse backup: $BACKUP"
cp --sparse=always "$DISK" "$BACKUP"
debugfs -w -R 'unlink /etc/passwd' "$DISK" >/dev/null
debugfs -w -R "write $TMP /etc/passwd" "$DISK" >/dev/null
debugfs -w -R 'set_inode_field /etc/passwd uid 0' "$DISK" >/dev/null
debugfs -w -R 'set_inode_field /etc/passwd gid 0' "$DISK" >/dev/null
debugfs -w -R 'set_inode_field /etc/passwd mode 0100644' "$DISK" >/dev/null
ROOT_LINE="$(debugfs -R 'cat /etc/passwd' "$DISK" 2>/dev/null | sed -n '1p')"
[ "$ROOT_LINE" = 'root::0:0:root:/root:/bin/sh' ] || { echo "verification failed; restore $BACKUP" >&2; exit 1; }
echo 'Root local-login recovery applied and verified. Boot normally, log in as root with an empty password, then run passwd.'
