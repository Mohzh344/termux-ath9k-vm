#!/usr/bin/env bash
# Shared storage helpers for the unified Full + Lite release.
# This file is sourced by launchers and host-side maintenance commands.

vm_default_state_root() {
  if [ -n "${VM_STATE_ROOT:-}" ]; then
    printf '%s\n' "$VM_STATE_ROOT"
  elif [ -n "${XDG_DATA_HOME:-}" ]; then
    printf '%s\n' "$XDG_DATA_HOME/android-wifi-monitor-injection-rootless"
  else
    printf '%s\n' "${HOME:-.}/.local/share/android-wifi-monitor-injection-rootless"
  fi
}

vm_storage_init() {
  VM_STATE_ROOT="${VM_STATE_ROOT:-$(vm_default_state_root)}"
  export VM_STATE_ROOT
  local base_dir="$1"
  local full_dir="${2:-$base_dir/full}"
  local lite_dir="${3:-$base_dir/lite}"
  local source_full="$full_dir/guest/alpine-ath9k.img"
  local source_lite="$lite_dir/guest/alpine-ath9k-v030-lite.img"
  local target_full="$VM_STATE_ROOT/full/alpine-ath9k.img"
  local target_lite="$VM_STATE_ROOT/lite/alpine-ath9k-v030-lite.img"

  mkdir -p "$VM_STATE_ROOT/full" "$VM_STATE_ROOT/lite" \
    "$VM_STATE_ROOT/backups" "$VM_STATE_ROOT/exports"

  vm_adopt_image "$source_full" "$target_full" Full
  vm_adopt_image "$source_lite" "$target_lite" Lite
  printf '%s\n' "$VM_STATE_ROOT"
}

vm_adopt_image() {
  local source="$1" target="$2" label="$3"
  [ -f "$target" ] && return 0
  [ -f "$source" ] || return 0
  mkdir -p "$(dirname "$target")"
  if [ "$source" = "$target" ]; then
    return 0
  fi
  # Move first so the initial adoption uses no extra blocks on the same
  # filesystem. A hard link is intentionally avoided: overwriting the bundled
  # file while extracting a later release would otherwise mutate the user's
  # persistent image through the link.
  if mv "$source" "$target" 2>/dev/null; then
    printf 'Adopted %s image into persistent storage: %s\n' "$label" "$target" >&2
  else
    cp --sparse=always --reflink=auto "$source" "$target"
    rm -f -- "$source"
    printf 'Copied %s image into persistent storage: %s\n' "$label" "$target" >&2
  fi
}

vm_cleanup_bundled_image() {
  local source="$1" target="$2" label="$3"
  [ -f "$target" ] || return 0
  [ -f "$source" ] || return 0
  [ "$source" = "$target" ] && return 0
  vm_require_offline_image "$target" || return 1
  rm -f -- "$source"
  printf 'Removed redundant bundled %s image; persistent copy remains at %s\n' "$label" "$target" >&2
}

vm_qemu_uses_image() {
  local image="$1"
  ps -eo args= 2>/dev/null | grep -F 'qemu-system-aarch64' | \
    grep -F -- "$image" | grep -vF -- 'grep -F' >/dev/null 2>&1
}

vm_require_offline_image() {
  local image="$1"
  [ -f "$image" ] || { printf 'missing image: %s\n' "$image" >&2; return 1; }
  if vm_qemu_uses_image "$image"; then
    printf 'refusing to modify a running image: %s\n' "$image" >&2
    return 1
  fi
  command -v debugfs >/dev/null 2>&1 || { printf 'missing debugfs; install e2fsprogs\n' >&2; return 1; }
  command -v e2fsck >/dev/null 2>&1 || { printf 'missing e2fsck; install e2fsprogs\n' >&2; return 1; }
}

vm_validate_image() {
  local image="$1"
  vm_require_offline_image "$image" || return 1
  e2fsck -fn "$image" >/dev/null
}

vm_backup_image() {
  local image="$1" label="${2:-manual}" destination_root="${3:-$(vm_default_state_root)/backups}"
  vm_require_offline_image "$image" || return 1
  mkdir -p "$destination_root"
  local stamp destination
  stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  destination="$destination_root/$(basename "$image").$label.$stamp.bak"
  cp --sparse=always --reflink=auto "$image" "$destination"
  printf '%s\n' "$destination"
}

vm_debugfs_quote() {
  # debugfs accepts double-quoted paths. Escape the two characters that can
  # otherwise change the command parser's interpretation.
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; 1s/^/"/; $s/$/"/'
}

vm_guest_path_exists() {
  local image="$1" guest_path="$2"
  debugfs -R "stat $guest_path" "$image" 2>&1 | grep -qE 'Inode:[[:space:]]+[0-9]+'
}

vm_guest_mkdir_p() {
  local image="$1" guest_path="$2" part current
  [ "$guest_path" = / ] && return 0
  current=""
  local oldifs="$IFS"
  IFS=/
  # shellcheck disable=SC2086
  set -- $guest_path
  IFS="$oldifs"
  for part in "$@"; do
    [ -n "$part" ] || continue
    current="$current/$part"
    if ! vm_guest_path_exists "$image" "$current"; then
      debugfs -w -R "mkdir $current" "$image" >/dev/null
    fi
  done
}

vm_guest_write_file() {
  local image="$1" local_file="$2" guest_file="$3" mode="${4:-0100644}"
  vm_guest_mkdir_p "$image" "$(dirname "$guest_file")"
  local q_local q_guest
  q_local="$(vm_debugfs_quote "$local_file")"
  q_guest="$(vm_debugfs_quote "$guest_file")"
  debugfs -w -R "rm $q_guest" "$image" >/dev/null 2>&1 || true
  debugfs -w -R "write $q_local $q_guest" "$image" >/dev/null
  debugfs -w -R "set_inode_field $q_guest uid 0" "$image" >/dev/null
  debugfs -w -R "set_inode_field $q_guest gid 0" "$image" >/dev/null
  debugfs -w -R "set_inode_field $q_guest mode $mode" "$image" >/dev/null
}

vm_guest_set_mode() {
  local image="$1" guest_path="$2" mode="$3"
  debugfs -w -R "set_inode_field $guest_path mode $mode" "$image" >/dev/null
}

vm_guest_cat() {
  local image="$1" guest_path="$2"
  debugfs -R "cat $guest_path" "$image" 2>/dev/null
}
