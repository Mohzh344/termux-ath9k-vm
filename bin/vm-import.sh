#!/usr/bin/env bash
set -eu

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=../src/vm-storage-lib.sh
. "$BASE_DIR/src/vm-storage-lib.sh"

usage() {
  cat <<'EOF'
Usage: bin/vm-import.sh --full|--lite EXPORT.tar.gz [--no-backup]

Import portable user data into a stopped persistent guest image. The target
image is never replaced. Authentication, init configuration, repositories,
kernels, firmware, and modules are intentionally not imported.
EOF
}

variant=""
archive=""
no_backup=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --full) variant=full ;;
    --lite) variant=lite ;;
    --no-backup) no_backup=1 ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      [ -z "$archive" ] || { echo 'Only one export archive may be supplied.' >&2; exit 2; }
      archive="$1"
      ;;
  esac
  shift
done
[ -n "$variant" ] || { echo 'Choose --full or --lite.' >&2; usage >&2; exit 2; }
[ -n "$archive" ] || { echo 'Specify an export archive.' >&2; usage >&2; exit 2; }
[ -f "$archive" ] || { echo "missing export: $archive" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo 'missing tar.' >&2; exit 1; }

VM_STATE_ROOT="${VM_STATE_ROOT:-$(vm_default_state_root)}"
vm_storage_init "$BASE_DIR" >/dev/null
if [ "$variant" = full ]; then
  image="$VM_STATE_ROOT/full/alpine-ath9k.img"
else
  image="$VM_STATE_ROOT/lite/alpine-ath9k-v030-lite.img"
fi
vm_require_offline_image "$image"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/vm-import.XXXXXX")"
cleanup() { rm -rf -- "$WORK"; }
trap cleanup EXIT INT TERM
mkdir -p "$WORK/extract"
# Refuse absolute paths and parent traversal even though exports are generated
# by this project. This also protects users who received an archive externally.
tar -tzf "$archive" >/dev/null
if tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(\/|$))'; then
  echo 'refusing an export containing absolute or parent-traversal paths.' >&2
  exit 1
fi
tar -xzf "$archive" -C "$WORK/extract"
[ "$(sed -n 's/^format=//p' "$WORK/extract/MANIFEST" 2>/dev/null | head -1)" = 1 ] || {
  echo 'unsupported or missing export MANIFEST.' >&2; exit 1;
}

if [ "$no_backup" -eq 0 ]; then
  backup="$(vm_backup_image "$image" before-import)"
  printf 'Safety backup: %s\n' "$backup"
fi

copy_tree() {
  local tree="$1" guest_root="$2" source
  source="$WORK/extract/$tree"
  [ -d "$source" ] || return 0
  # Find relative paths on the extracted host tree. The allow-list of top-level
  # names is fixed below; no archive path is ever used as a guest path directly.
  while IFS= read -r -d '' local_file; do
    rel="${local_file#"$source"/}"
    guest_file="$guest_root/$rel"
    mode="$(stat -c '%a' "$local_file")"
    if (( 8#$mode & 0111 )); then
      guest_mode="0100755"
    else
      guest_mode="0100644"
    fi
    vm_guest_write_file "$image" "$local_file" "$guest_file" "$guest_mode"
  done < <(find "$source" -mindepth 1 -type f -print0)
  while IFS= read -r -d '' local_dir; do
    rel="${local_dir#"$source"/}"
    vm_guest_mkdir_p "$image" "$guest_root/$rel"
    mode="$(stat -c '%a' "$local_dir")"
    vm_guest_set_mode "$image" "$guest_root/$rel" "040$mode" >/dev/null 2>&1 || true
  done < <(find "$source" -mindepth 1 -type d -print0)
}

copy_tree root /root
copy_tree home /home
copy_tree opt /opt
copy_tree usr/local /usr/local
copy_tree etc/profile.d /etc/profile.d

if [ -s "$WORK/extract/etc/apk-world" ]; then
  vm_guest_mkdir_p "$image" /root/.vm-migration
  vm_guest_write_file "$image" "$WORK/extract/etc/apk-world" /root/.vm-migration/apk-world 0100600
  cat > "$WORK/apply-packages.sh" <<'EOF'
#!/bin/sh
set -eu
WORLD=/root/.vm-migration/apk-world
[ -s "$WORLD" ] || { echo "No exported apk world found: $WORLD" >&2; exit 1; }
command -v apk >/dev/null 2>&1 || { echo 'apk is not available in this guest.' >&2; exit 1; }
set -- $(awk 'NF && $1 !~ /^#/ {print $1}' "$WORLD")
[ "$#" -gt 0 ] || { echo 'The exported apk world is empty.'; exit 0; }
echo "Installing exported explicitly requested packages..."
apk add --no-cache "$@"
printf 'Package migration complete.\n'
EOF
  vm_guest_write_file "$image" "$WORK/apply-packages.sh" /root/.vm-migration/apply-packages.sh 0100700
fi

vm_validate_image "$image"
printf 'Import complete into %s.\n' "$image"
printf 'Portable files and persistent PATH settings were restored.\n'
if [ -s "$WORK/extract/etc/apk-world" ]; then
  printf 'After booting with Internet enabled, run:\n  /root/.vm-migration/apply-packages.sh\n'
fi
