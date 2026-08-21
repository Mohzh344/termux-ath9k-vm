#!/usr/bin/env bash
set -eu

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=../src/vm-storage-lib.sh
. "$BASE_DIR/src/vm-storage-lib.sh"

usage() {
  cat <<'EOF'
Usage: bin/vm-backup.sh --full|--lite [--output DIR]

Create a sparse-aware backup of the persistent Full or Lite image.
The VM must be stopped before a backup is taken.
EOF
}

variant=""
out_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --full) variant=full ;;
    --lite) variant=lite ;;
    --output)
      shift
      [ "$#" -gt 0 ] || { echo '--output requires a directory.' >&2; exit 2; }
      out_dir="$1"
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
[ -n "$out_dir" ] || out_dir="$VM_STATE_ROOT/backups"
backup="$(vm_backup_image "$image" manual "$out_dir")"
printf 'Backup created:\n  %s\n' "$backup"
printf 'Restore it only while the VM is stopped, using cp --sparse=always.\n'
