#!/usr/bin/env bash
# Unified host-side administration command for the Android Wi-Fi VM project.
# Compatibility wrappers call this file so each management domain has one
# implementation instead of several divergent scripts.
set -Eeuo pipefail

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=../src/vm-storage-lib.sh
. "$BASE_DIR/src/vm-storage-lib.sh"

VM_STATE_ROOT="${VM_STATE_ROOT:-$(vm_default_state_root)}"
export VM_STATE_ROOT

usage() {
  cat <<'EOF'
Usage: bin/vmctl.sh COMMAND [OPTIONS]

Commands:
  doctor [--full|--lite]       Check host, release, storage, image and USB readiness.
  info [--full|--lite]         Show persistent image, auth, PATH and filesystem information.
  status                      Show running QEMU processes and persistent image state.
  backup --full|--lite         Create a sparse-aware image backup.
  export --full|--lite         Export portable user files and the apk world list.
  import --full|--lite FILE    Import a portable export into a stopped image.
  resize --full|--lite SIZE    Grow a stopped image, for example 3G or 4096M.
  path add --full|--lite DIR   Persist an absolute tool directory in guest PATH.
  path list --full|--lite      Show managed persistent PATH entries.
  usb                         Diagnose Android-visible USB prerequisites.

The legacy vm-backup.sh, vm-export.sh and vm-import.sh commands remain supported
as compatibility wrappers around this interface.
EOF
}

say() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

variant_from_args() {
  local v="${VM_VARIANT:-}"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --full) v=full ;;
      --lite) v=lite ;;
    esac
    shift
  done
  printf '%s\n' "$v"
}

image_for_variant() {
  local variant="$1"
  case "$variant" in
    full) printf '%s\n' "$VM_STATE_ROOT/full/alpine-ath9k.img" ;;
    lite) printf '%s\n' "$VM_STATE_ROOT/lite/alpine-ath9k-v030-lite.img" ;;
    *) die 'choose --full or --lite' ;;
  esac
}

bundle_dir_for_variant() {
  case "$1" in
    full) printf '%s\n' "${FULL_DIR:-$BASE_DIR/full}" ;;
    lite) printf '%s\n' "${LITE_DIR:-$BASE_DIR/lite}" ;;
    *) die 'choose full or lite' ;;
  esac
}

require_variant_image() {
  local variant="$1" image
  image="$(image_for_variant "$variant")"
  [ -f "$image" ] || die "persistent $variant image is missing: $image. Run bin/install-termux.sh first."
  printf '%s\n' "$image"
}

validate_variant_args() {
  local variant="$1"
  [ "$variant" = full ] || [ "$variant" = lite ] || die 'choose exactly one variant with --full or --lite'
}

image_size_bytes() { stat -c '%s' "$1"; }
image_allocated_bytes() { du -B1 "$1" | awk 'NR==1 {print $1}'; }

parse_size_bytes() {
  local input="$1" number suffix multiplier
  if [[ "$input" =~ ^([0-9]+)([KkMmGgTt]?)$ ]]; then
    number="${BASH_REMATCH[1]}"
    suffix="${BASH_REMATCH[2]}"
  else
    die "invalid size '$input'; use an integer with optional K, M, G or T"
  fi
  case "$suffix" in
    '') multiplier=1 ;;
    [Kk]) multiplier=1024 ;;
    [Mm]) multiplier=$((1024**2)) ;;
    [Gg]) multiplier=$((1024**3)) ;;
    [Tt]) multiplier=$((1024**4)) ;;
  esac
  awk -v n="$number" -v m="$multiplier" 'BEGIN { printf "%.0f\n", n*m }'
}

managed_path_file=/etc/profile.d/vmctl-path.sh
VMCTL_LOCK_IMAGE=""
WORK_CLEANUP=""

vmctl_cleanup() {
  if [ -n "${WORK_CLEANUP:-}" ]; then rm -rf -- "$WORK_CLEANUP"; fi
  if [ -n "${VMCTL_LOCK_IMAGE:-}" ]; then vm_unlock_image "$VMCTL_LOCK_IMAGE"; fi
}

vmctl_acquire_image() {
  local image="$1"
  vm_lock_image "$image" >/dev/null || die "could not acquire image operation lock: $image"
  VMCTL_LOCK_IMAGE="$image"
  trap vmctl_cleanup EXIT
}

read_managed_paths() {
  local image="$1"
  if vm_guest_path_exists "$image" "$managed_path_file"; then
    vm_guest_cat "$image" "$managed_path_file" | sed -n 's/^[[:space:]]*# vmctl-path: //p'
  fi
}

write_managed_path() {
  local image="$1" path="$2" tmp current
  tmp="$(mktemp "${TMPDIR:-/tmp}/vmctl-path.XXXXXX")"
  if vm_guest_path_exists "$image" "$managed_path_file"; then
    vm_guest_cat "$image" >"$tmp"
  else
    : >"$tmp"
  fi
  if grep -Fqx "# vmctl-path: $path" "$tmp"; then
    say "PATH entry already exists: $path"
    rm -f -- "$tmp"
    return 0
  fi
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' '# Managed by vmctl; persistent across reboot and release updates.'
    while IFS= read -r current; do
      [ -n "$current" ] || continue
      printf 'case ":${PATH:-}:" in *":%s:"*) ;; *) PATH="${PATH:+$PATH:}%s"; export PATH ;; esac\n' "$current" "$current"
    done < <(sed -n 's/^[[:space:]]*# vmctl-path: //p' "$tmp")
    printf '# vmctl-path: %s\n' "$path"
    printf 'case ":${PATH:-}:" in *":%s:"*) ;; *) PATH="${PATH:+$PATH:}%s"; export PATH ;; esac\n' "$path" "$path"
  } >"$tmp.new"
  vm_guest_write_file "$image" "$tmp.new" "$managed_path_file" 0100644
  rm -f -- "$tmp" "$tmp.new"
  say "Persistent PATH entry added: $path"
}

cmd_status() {
  say "VM_STATE_ROOT=$VM_STATE_ROOT"
  if pgrep -af qemu-system-aarch64 2>/dev/null; then :; else say 'No qemu-system-aarch64 process is running.'; fi
  for variant in full lite; do
    image="$(image_for_variant "$variant")"
    if [ -f "$image" ]; then
      printf '%s image: present, size=%s bytes, allocated=%s bytes\n' "$variant" "$(image_size_bytes "$image")" "$(image_allocated_bytes "$image")"
      if vm_qemu_uses_image "$image"; then say "  state: RUNNING (do not modify)"; else say '  state: stopped'; fi
    else
      printf '%s image: MISSING (%s)\n' "$variant" "$image"
    fi
  done
}

check_command() {
  local name="$1" required="$2"
  if command -v "$name" >/dev/null 2>&1; then
    printf '[PASS] %-18s %s\n' "$name" "$(command -v "$name")"
  elif [ "$required" = 1 ]; then
    printf '[FAIL] %-18s missing\n' "$name"
    return 1
  else
    printf '[WARN] %-18s unavailable\n' "$name"
  fi
}

check_image_doctor() {
  local variant="$1" image bundle rc=0
  image="$(image_for_variant "$variant")"
  bundle="$(bundle_dir_for_variant "$variant")"
  if [ -f "$image" ]; then
    printf '[PASS] %-18s %s\n' "$variant image" "$image"
    if e2fsck -fn "$image" >/dev/null 2>&1; then
      printf '[PASS] %-18s ext4 clean\n' "$variant filesystem"
    else
      printf '[FAIL] %-18s e2fsck reported an error\n' "$variant filesystem"
      rc=1
    fi
    if vm_qemu_uses_image "$image"; then
      printf '[WARN] %-18s image is currently used by QEMU\n' "$variant lock"
    else
      printf '[PASS] %-18s image is stopped\n' "$variant lock"
    fi
  else
    printf '[WARN] %-18s missing; installer will adopt a bundled image if available\n' "$variant image"
    rc=1
  fi
  if [ -d "$bundle/guest" ]; then
    printf '[PASS] %-18s %s\n' "$variant release" "$bundle"
  else
    printf '[WARN] %-18s release directory missing\n' "$variant release"
    rc=1
  fi
  return "$rc"
}

cmd_doctor() {
  local requested="$(variant_from_args "$@")" rc=0
  say 'Android Wi-Fi VM readiness report'
  printf 'VM_STATE_ROOT: %s\n' "$VM_STATE_ROOT"
  printf 'Host architecture: %s\n' "$(uname -m)"
  [ "$(uname -m)" = aarch64 ] || warn 'This host is not aarch64; Android Termux normally is. QEMU tests may still work under emulation.'
  check_command bash 1 || rc=1
  check_command qemu-system-aarch64 1 || rc=1
  check_command e2fsck 1 || rc=1
  check_command debugfs 1 || rc=1
  check_command resize2fs 0 || true
  check_command socat 0 || true
  check_command termux-usb 0 || true
  check_command pkg 0 || true
  if command -v df >/dev/null 2>&1; then
    df -h "$VM_STATE_ROOT" | tail -1 | awk '{printf "Storage free: %s\n", $4}'
  fi
  if [ -n "$requested" ]; then
    validate_variant_args "$requested"
    check_image_doctor "$requested" || rc=1
  else
    check_image_doctor full || rc=1
    check_image_doctor lite || rc=1
  fi
  if command -v termux-usb >/dev/null 2>&1; then
    if raw="$(termux-usb -l 2>&1)"; then
      printf '[INFO] %-18s %s\n' 'Android USB' "$raw"
      printf '%s\n' "$raw" | grep -q '0cf3\|9271' && printf '[PASS] %-18s AR9271 (0cf3:9271) is listed\n' 'AR9271' || printf '[WARN] %-18s AR9271 is not currently listed\n' 'AR9271'
    else
      printf '[WARN] %-18s termux-usb -l failed: %s\n' 'Android USB' "$raw"
    fi
  else
    printf '[INFO] %-18s install Termux:API to inspect Android USB devices\n' 'Android USB'
  fi
  return "$rc"
}

cmd_info() {
  local requested="$(variant_from_args "$@")"
  local variants=(full lite) variant image inittab paths
  [ -n "$requested" ] && variants=("$requested")
  for variant in "${variants[@]}"; do
    image="$(image_for_variant "$variant")"
    printf '\n[%s]\n' "${variant^^}"
    printf 'image=%s\n' "$image"
    if [ ! -f "$image" ]; then say 'state=missing'; continue; fi
    printf 'state=%s\n' "$(vm_qemu_uses_image "$image" && printf running || printf stopped)"
    printf 'size_bytes=%s\n' "$(image_size_bytes "$image")"
    printf 'allocated_bytes=%s\n' "$(image_allocated_bytes "$image")"
    if inittab="$(vm_guest_cat "$image" /etc/inittab 2>/dev/null)"; then
      printf 'auth_entry=%s\n' "$(printf '%s\n' "$inittab" | grep '^ttyAMA0:' | tail -1 | sed 's/^ttyAMA0:[^:]*:[^:]*://' || printf unknown)"
    fi
    printf 'managed_path_entries=\n'
    paths="$(read_managed_paths "$image" || true)"
    [ -n "$paths" ] && printf '  %s\n' "$paths" || printf '  none\n'
    if vm_guest_path_exists "$image" /etc/apk/world; then
      printf 'apk_world_count=%s\n' "$(vm_guest_cat "$image" /etc/apk/world | awk 'NF && $1 !~ /^#/ {n++} END{print n+0}')"
    fi
  done
}

cmd_backup() {
  local variant="$(variant_from_args "$@")" image out=""
  validate_variant_args "$variant"
  while [ "$#" -gt 0 ]; do
    case "$1" in --output) shift; out="${1:-}" ;; esac
    shift
  done
  image="$(require_variant_image "$variant")"
  local backup
  backup="$(vm_backup_image "$image" manual "${out:-$VM_STATE_ROOT/backups}")"
  printf 'Backup created:\n  %s\n' "$backup"
}

cmd_export() {
  local variant="$(variant_from_args "$@")" image out_file=""
  validate_variant_args "$variant"
  while [ "$#" -gt 0 ]; do
    case "$1" in --output) shift; out_file="${1:-}" ;; esac
    shift
  done
  image="$(require_variant_image "$variant")"
  vm_require_offline_image "$image"
  vmctl_acquire_image "$image"
  [ -n "$out_file" ] || out_file="$VM_STATE_ROOT/exports/${variant}-user-data-$(date -u '+%Y%m%dT%H%M%SZ').tar.gz"
  local tree errors guest_dir destination
  work="$(mktemp -d "${TMPDIR:-/tmp}/vmctl-export.XXXXXX")"
  WORK_CLEANUP="$work"
  tree="$work/tree"
  mkdir -p "$tree/etc"
  for guest_dir in /root /home /opt /usr/local; do
    vm_guest_path_exists "$image" "$guest_dir" || continue
    destination="$tree"
    errors="$work/rdump-errors"
    : >"$errors"
    debugfs -R "rdump $guest_dir $destination" "$image" >/dev/null 2>"$errors"
    if grep -vE '^(debugfs [0-9]|dump_file: Operation not permitted while changing ownership)' "$errors" | grep -q '[^[:space:]]'; then
      cat "$errors" >&2; return 1
    fi
  done
  if vm_guest_path_exists "$image" /etc/profile.d; then
    debugfs -R "rdump /etc/profile.d $tree/etc" "$image" >/dev/null 2>"$work/profile-errors" || return 1
  fi
  if vm_guest_path_exists "$image" /etc/apk/world; then
    debugfs -R "dump -p /etc/apk/world $tree/etc/apk-world" "$image" >/dev/null 2>"$work/world-errors"
    if grep -vE '^(debugfs [0-9]|dump_file: Operation not permitted while changing ownership)' "$work/world-errors" | grep -q '[^[:space:]]'; then
      cat "$work/world-errors" >&2
      return 1
    fi
  fi
  cat >"$tree/MANIFEST" <<EOF
format=1
variant=$variant
source_image=$(basename "$image")
created_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
portable_paths=/root,/home,/opt,/usr/local,/etc/profile.d
package_world=etc/apk-world
excluded=/etc/shadow,/etc/passwd,/etc/inittab,/etc/apk/repositories,/lib/modules,/boot
EOF
  cat >"$tree/README.txt" <<'EOF'
This portable export contains user data and explicitly requested apk packages.
It is not a bootable image. Authentication, init configuration, repositories,
kernels, firmware and modules are deliberately excluded.
EOF
  mkdir -p "$(dirname "$out_file")"
  rm -f -- "$out_file"
  tar --numeric-owner --sort=name -czf "$out_file" -C "$tree" .
  sha256sum "$out_file" >"$out_file.sha256"
  printf 'Portable export created:\n  %s\nSHA-256 manifest:\n  %s\n' "$out_file" "$out_file.sha256"
}

cmd_import() {
  local variant="$(variant_from_args "$@")" archive="" no_backup=0 image
  validate_variant_args "$variant"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --no-backup) no_backup=1 ;;
      --full|--lite) ;;
      -*) die "unknown import option: $1" ;;
      *) [ -z "$archive" ] || die 'only one export archive may be supplied'; archive="$1" ;;
    esac
    shift
  done
  [ -n "$archive" ] || die 'specify an export archive'
  [ -f "$archive" ] || die "missing export: $archive"
  image="$(require_variant_image "$variant")"
  vm_require_offline_image "$image"
  work="$(mktemp -d "${TMPDIR:-/tmp}/vmctl-import.XXXXXX")"
  WORK_CLEANUP="$work"
  mkdir -p "$work/extract"
  tar -tzf "$archive" >/dev/null
  if tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(\/|$))'; then die 'refusing absolute or parent-traversal paths'; fi
  tar -xzf "$archive" -C "$work/extract"
  [ "$(sed -n 's/^format=//p' "$work/extract/MANIFEST" 2>/dev/null | head -1)" = 1 ] || die 'unsupported or missing export MANIFEST'
  if [ "$no_backup" -eq 0 ]; then
    printf 'Safety backup: %s\n' "$(vm_backup_image "$image" before-import)"
  fi
  vmctl_acquire_image "$image"
  local tree source local_file rel guest_file mode guest_mode local_dir
  copy_tree() {
    tree="$1"; guest_root="$2"; source="$work/extract/$tree"
    [ -d "$source" ] || return 0
    while IFS= read -r -d '' local_file; do
      rel="${local_file#"$source"/}"; guest_file="$guest_root/$rel"; mode="$(stat -c '%a' "$local_file")"
      if (( 8#$mode & 0111 )); then guest_mode=0100755; else guest_mode=0100644; fi
      vm_guest_write_file "$image" "$local_file" "$guest_file" "$guest_mode"
    done < <(find "$source" -mindepth 1 -type f -print0)
    while IFS= read -r -d '' local_dir; do
      rel="${local_dir#"$source"/}"; vm_guest_mkdir_p "$image" "$guest_root/$rel"
    done < <(find "$source" -mindepth 1 -type d -print0)
  }
  copy_tree root /root; copy_tree home /home; copy_tree opt /opt; copy_tree usr/local /usr/local; copy_tree etc/profile.d /etc/profile.d
  if [ -s "$work/extract/etc/apk-world" ]; then
    vm_guest_mkdir_p "$image" /root/.vm-migration
    vm_guest_write_file "$image" "$work/extract/etc/apk-world" /root/.vm-migration/apk-world 0100600
    cat >"$work/apply-packages.sh" <<'EOF'
#!/bin/sh
set -eu
WORLD=/root/.vm-migration/apk-world
[ -s "$WORLD" ] || { echo "No exported apk world found: $WORLD" >&2; exit 1; }
command -v apk >/dev/null 2>&1 || { echo 'apk is unavailable.' >&2; exit 1; }
set -- $(awk 'NF && $1 !~ /^#/ {print $1}' "$WORLD")
[ "$#" -gt 0 ] || exit 0
apk add --no-cache "$@"
EOF
    vm_guest_write_file "$image" "$work/apply-packages.sh" /root/.vm-migration/apply-packages.sh 0100700
  fi
  vm_validate_image "$image"
  printf 'Import complete into %s.\n' "$image"
}

cmd_resize() {
  local variant="$(variant_from_args "$@")" requested="" image target backup current
  validate_variant_args "$variant"
  while [ "$#" -gt 0 ]; do case "$1" in --full|--lite) ;; *) requested="$1" ;; esac; shift; done
  [ -n "$requested" ] || die 'resize requires a target size, for example 3G'
  image="$(require_variant_image "$variant")"
  vm_require_offline_image "$image"
  command -v truncate >/dev/null 2>&1 || die 'truncate is required for resize'
  command -v resize2fs >/dev/null 2>&1 || die 'resize2fs is required; install e2fsprogs'
  target="$(parse_size_bytes "$requested")"; current="$(image_size_bytes "$image")"
  [ "$target" -gt "$current" ] || die "resize only grows images; current=${current} target=${target}"
  backup="$(vm_backup_image "$image" before-resize)"
  vmctl_acquire_image "$image"
  if e2fsck -fy "$image" >/dev/null 2>&1; then
    :
  else
    fsck_rc=$?
    case "$fsck_rc" in
      1|2) : ;; # e2fsck repaired the offline filesystem; continue.
      *)
        warn "e2fsck failed; restoring backup $backup"
        cp --sparse=always --reflink=auto "$backup" "$image"
        die 'filesystem check failed; original image was restored'
        ;;
    esac
  fi
  truncate -s "$target" "$image"
  if ! resize2fs "$image" >/dev/null; then
    warn "resize2fs failed; restoring backup $backup"
    cp --sparse=always --reflink=auto "$backup" "$image"
    die 'filesystem resize failed; original image was restored'
  fi
  vm_validate_image "$image"
  printf 'Image grown successfully:\n  image=%s\n  old_bytes=%s\n  new_bytes=%s\n  backup=%s\n' "$image" "$current" "$target" "$backup"
}

cmd_path() {
  local action="${1:-}" variant path image
  shift || true
  case "$action" in
    add)
      variant="$(variant_from_args "$@")"
      while [ "$#" -gt 0 ]; do case "$1" in --full|--lite) ;; *) path="$1" ;; esac; shift; done
      validate_variant_args "$variant"; [[ "$path" = /* ]] || die 'PATH directory must be absolute'; [[ "$path" != *$'\n'* ]] || die 'PATH directory cannot contain a newline'; [[ "$path" =~ ^/[A-Za-z0-9._/@+%=-]+$ ]] || die 'PATH directory contains unsupported shell characters'
      image="$(require_variant_image "$variant")"; vm_require_offline_image "$image"; vmctl_acquire_image "$image"; write_managed_path "$image" "$path" ;;
    list)
      variant="$(variant_from_args "$@")"; validate_variant_args "$variant"; image="$(require_variant_image "$variant")"; read_managed_paths "$image" || true ;;
    *) die 'path requires add or list' ;;
  esac
}

cmd_usb() {
  check_command termux-usb 0 || true
  check_command socat 0 || true
  check_command qemu-system-aarch64 0 || true
  if command -v termux-usb >/dev/null 2>&1; then
    local raw
    raw="$(termux-usb -l 2>&1)" || { warn "termux-usb -l failed: $raw"; return 1; }
    printf 'Android-visible USB devices: %s\n' "$raw"
    if printf '%s\n' "$raw" | grep -q '0cf3\|9271'; then
      say 'AR9271 signature (0cf3:9271) detected. Permission is not granted automatically by this diagnostic.'
    else
      say 'AR9271 signature was not detected. Connect the adapter and run termux-usb -l again.'
    fi
  else
    say 'Install Termux:API and the termux-api package to inspect Android USB devices.'
  fi
}

main() {
  local command="${1:-help}"
  shift || true
  case "$command" in
    doctor) cmd_doctor "$@" ;;
    info) cmd_info "$@" ;;
    status) cmd_status "$@" ;;
    backup) cmd_backup "$@" ;;
    export) cmd_export "$@" ;;
    import) cmd_import "$@" ;;
    resize) cmd_resize "$@" ;;
    path) cmd_path "$@" ;;
    usb) cmd_usb "$@" ;;
    help|-h|--help) usage ;;
    *) die "unknown command: $command (use help)" ;;
  esac
}
main "$@"
