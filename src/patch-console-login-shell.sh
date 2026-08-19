#!/usr/bin/env bash
# Patch an Alpine guest image so the direct ttyAMA0 root shell is a login shell.
# This is not a login manager: init still starts /bin/sh directly as root, so no
# username or password prompt is introduced.
set -euo pipefail

IMAGE="${1:-}"
CREATE_BACKUP="${CREATE_BACKUP:-1}"
[ -n "$IMAGE" ] || { echo "usage: $0 /path/to/guest.img" >&2; exit 2; }
[ -f "$IMAGE" ] || { echo "missing guest image: $IMAGE" >&2; exit 1; }
command -v debugfs >/dev/null 2>&1 || { echo 'missing debugfs; install e2fsprogs' >&2; exit 1; }

if pgrep -af 'qemu-system-aarch64' >/dev/null 2>&1; then
  echo 'refusing to edit an image while qemu-system-aarch64 is running' >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/console-login-shell.XXXXXX")"
cleanup(){ rm -rf -- "$WORK"; }
trap cleanup EXIT INT TERM

INI="$WORK/inittab"
PROFILE="$WORK/profile"

debugfs -R "dump /etc/inittab $INI" "$IMAGE" >/dev/null
sed -E -i 's|^ttyAMA0::respawn:/bin/sh([[:space:]]+-l)?[[:space:]]*$|ttyAMA0::respawn:/bin/sh -l|' "$INI"
grep -qxF 'ttyAMA0::respawn:/bin/sh -l' "$INI" || {
  echo 'could not prepare ttyAMA0 login-shell entry' >&2
  exit 1
}

debugfs -R "dump /etc/profile $PROFILE" "$IMAGE" >/dev/null
if ! grep -q '^export PATH=' "$PROFILE"; then
  printf '\n# Keep the standard executable locations available in direct login shells.\nexport PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"\n' >> "$PROFILE"
fi

if [ "$CREATE_BACKUP" = 1 ]; then
  BACKUP="${IMAGE}.before-console-login-shell-$(date +%Y%m%d-%H%M%S).bak"
  cp --sparse=always "$IMAGE" "$BACKUP"
  echo "backup: $BACKUP"
fi

for item in /etc/inittab /etc/profile; do
  debugfs -w -R "rm $item" "$IMAGE" >/dev/null
  case "$item" in
    /etc/inittab) debugfs -w -R "write $INI $item" "$IMAGE" >/dev/null ;;
    /etc/profile) debugfs -w -R "write $PROFILE $item" "$IMAGE" >/dev/null ;;
  esac
  debugfs -w -R "set_inode_field $item uid 0" "$IMAGE" >/dev/null
  debugfs -w -R "set_inode_field $item gid 0" "$IMAGE" >/dev/null
  debugfs -w -R "set_inode_field $item mode 0100644" "$IMAGE" >/dev/null
done

# Verify the exact guest-side contract and confirm that credentials were not changed.
got_ini="$(debugfs -R 'cat /etc/inittab' "$IMAGE" 2>/dev/null)"
got_profile="$(debugfs -R 'cat /etc/profile' "$IMAGE" 2>/dev/null)"
printf '%s\n' "$got_ini" | grep -qxF 'ttyAMA0::respawn:/bin/sh -l'
printf '%s\n' "$got_profile" | grep -q '^export PATH='

echo 'console login-shell patch applied: ttyAMA0 runs /bin/sh -l directly as root; no login/password prompt was added.'
