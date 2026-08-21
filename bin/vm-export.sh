#!/bin/sh
set -eu

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=../src/vm-storage-lib.sh
. "$BASE_DIR/src/vm-storage-lib.sh"

usage() {
  cat <<'EOF'
Usage: bin/vm-export.sh --full|--lite [--output FILE]

Export portable user data from a stopped guest image. The export includes
/root, /home, /opt, /usr/local, /etc/profile.d, and /etc/apk/world.
It deliberately excludes /etc/shadow, /etc/inittab, repositories, kernels,
and other OS-specific state.
EOF
}

variant=""
out_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --full) variant=full ;;
    --lite) variant=lite ;;
    --output)
      shift
      [ "$#" -gt 0 ] || { echo '--output requires a file.' >&2; exit 2; }
      out_file="$1"
      ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ -n "$variant" ] || { echo 'Choose --full or --lite.' >&2; usage >&2; exit 2; }

VM_STATE_ROOT="${VM_STATE_ROOT:-$(vm_default_state_root)}"
vm_storage_init "$BASE_DIR" >/dev/null
if [ "$variant" = full ]; then
  image="$VM_STATE_ROOT/full/alpine-ath9k.img"
else
  image="$VM_STATE_ROOT/lite/alpine-ath9k-v030-lite.img"
fi
vm_require_offline_image "$image"
[ -n "$out_file" ] || out_file="$VM_STATE_ROOT/exports/${variant}-user-data-$(date -u '+%Y%m%dT%H%M%SZ').tar.gz"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/vm-export.XXXXXX")"
cleanup() { rm -rf -- "$WORK"; }
trap cleanup EXIT INT TERM
TREE="$WORK/tree"
mkdir -p "$TREE/etc"

# debugfs rdump appends the source directory's basename to the destination.
# This preserves directory boundaries without mounting the guest image.
dump_dir() {
  local guest_dir="$1" destination="$2" errors
  vm_guest_path_exists "$image" "$guest_dir" || return 0
  mkdir -p "$destination"
  errors="$WORK/rdump-errors"
  : > "$errors"
  debugfs -R "rdump $guest_dir $destination" "$image" >/dev/null 2>"$errors"
  # debugfs attempts to chown extracted files to their guest UID. Termux users
  # normally cannot chown to arbitrary UIDs, so this warning is expected; file
  # contents and modes are still exported. Any other diagnostic is a failure.
  if grep -vE '^(debugfs [0-9]|dump_file: Operation not permitted while changing ownership)' "$errors" | grep -q '[^[:space:]]'; then
    cat "$errors" >&2
    return 1
  fi
}
dump_dir /root "$TREE"
dump_dir /home "$TREE"
dump_dir /opt "$TREE"
dump_dir /usr/local "$TREE"
dump_dir /etc/profile.d "$TREE/etc"

if vm_guest_path_exists "$image" /etc/apk/world; then
  debugfs -R "dump -p /etc/apk/world $TREE/etc/apk-world" "$image" >/dev/null
fi

cat > "$TREE/MANIFEST" <<EOF
format=1
variant=$variant
source_image=$(basename "$image")
created_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
portable_paths=/root,/home,/opt,/usr/local,/etc/profile.d
package_world=etc/apk-world
excluded=/etc/shadow,/etc/passwd,/etc/inittab,/etc/apk/repositories,/lib/modules,/boot
EOF
cat > "$TREE/README.txt" <<'EOF'
This is a portable user-data export for the Android Wi-Fi monitor/injection
rootless Alpine VM project.

It is intended to migrate user files and explicitly requested apk packages
between compatible Alpine ARM64 images. It is not a bootable disk image.
Authentication files, init configuration, repositories, kernels, firmware,
and modules are deliberately excluded and must not be copied between OS
images. The archive may contain private files from /root; keep it private.

To import into a new VM, run the host-side vm-import.sh while the target image
is stopped. Then boot the target with Internet enabled and run the generated
apply-packages command if you want to reinstall the exported apk world list.
EOF

mkdir -p "$(dirname "$out_file")"
rm -f -- "$out_file"
tar --numeric-owner --sort=name -czf "$out_file" -C "$TREE" .
sha256sum "$out_file" > "$out_file.sha256"
printf 'Portable export created:\n  %s\n' "$out_file"
printf 'SHA-256 manifest:\n  %s\n' "$out_file.sha256"
printf 'This export can contain private /root data; keep it protected.\n'
