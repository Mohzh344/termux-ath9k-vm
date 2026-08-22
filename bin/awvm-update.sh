#!/usr/bin/env bash
set -Eeuo pipefail

REPO="Mohzh344/android-wifi-monitor-injection-rootless"
API_URL="https://api.github.com/repos/$REPO/releases/latest"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${VM_STATE_ROOT:-}"
KEEP_OLD=0
CHECK_ONLY=0
YES=0
TMP_ROOT=""
OLD_DIR=""
CALLER_PWD="$(pwd -P 2>/dev/null || pwd)"
CWD_IN_PROJECT=0

say(){ printf '\n==> %s\n' "$*"; }
die(){ printf '\nERROR: %s\n' "$*" >&2; exit 1; }
warn(){ printf '\nWARNING: %s\n' "$*" >&2; }
cleanup(){ [ -z "$TMP_ROOT" ] || rm -rf -- "$TMP_ROOT"; }
validate_archive_paths(){
  local archive_file="$1" member normalized listing
  listing="$(tar --list --gzip --file "$archive_file")" || die 'could not list the downloaded archive safely'
  while IFS= read -r member; do
    normalized="${member#./}"
    case "$normalized" in
      /*|..|../*|*/../*) die "archive contains an unsafe path: $member" ;;
    esac
  done <<< "$listing"
}
trap cleanup EXIT INT TERM

usage(){
  cat <<'EOF'
Usage: bin/awvm-update.sh [OPTIONS]

Safely update this AWVM checkout from the latest GitHub Release.

Options:
  --check       Check the latest release without downloading or changing files.
  --yes         Do not ask before removing the old checkout after success.
  --keep-old    Keep a renamed backup of the old checkout after success.
  --help        Show this help.

Environment:
  VM_STATE_ROOT  External persistent Full/Lite image directory. If unset, the
                 existing project storage setting is used by install-termux.sh.
EOF
}

while (($#)); do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --yes) YES=1 ;;
    --keep-old) KEEP_OLD=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1 (use --help)" ;;
  esac
  shift
done

[ -d "$PROJECT_DIR" ] || die "project directory not found: $PROJECT_DIR"
[ ! -L "$PROJECT_DIR" ] || die "refusing to update a symbolic-link project directory: $PROJECT_DIR"
[ -f "$PROJECT_DIR/bin/install-termux.sh" ] || die "this does not look like an AWVM project checkout: $PROJECT_DIR"
[ -f "$PROJECT_DIR/bin/vm-launcher.sh" ] || die "vm-launcher.sh is missing from: $PROJECT_DIR"
case "$CALLER_PWD/" in
  "$PROJECT_DIR/"*) CWD_IN_PROJECT=1 ;;
esac
command -v curl >/dev/null 2>&1 || die 'curl is required; install it with: pkg install -y curl'
command -v sha256sum >/dev/null 2>&1 || die 'sha256sum is required; install coreutils'
command -v tar >/dev/null 2>&1 || die 'tar is required; install tar'
command -v pkg >/dev/null 2>&1 || die 'Run this updater inside Termux (pkg was not found).'

if [ -z "$STATE_DIR" ]; then
  if [ -n "${XDG_DATA_HOME:-}" ] && [ -d "$XDG_DATA_HOME/android-wifi-monitor-injection-rootless" ]; then
    STATE_DIR="$XDG_DATA_HOME/android-wifi-monitor-injection-rootless"
  elif [ -z "${XDG_DATA_HOME:-}" ] && [ -d "$HOME/.local/share/android-wifi-monitor-injection-rootless" ]; then
    STATE_DIR="$HOME/.local/share/android-wifi-monitor-injection-rootless"
  elif [ -n "${XDG_DATA_HOME:-}" ]; then
    STATE_DIR="$XDG_DATA_HOME/awvm"
  else
    STATE_DIR="$HOME/.local/share/awvm"
  fi
fi
state_parent="$(dirname -- "$STATE_DIR")"
mkdir -p -- "$state_parent"
STATE_DIR="$(CDPATH= cd -- "$state_parent" && pwd)/$(basename -- "$STATE_DIR")"
case "$STATE_DIR/" in
  "$PROJECT_DIR/"*) die "VM_STATE_ROOT must be outside the project checkout: $STATE_DIR" ;;
esac

metadata="$(curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 \
  -H 'Accept: application/vnd.github+json' -A 'awvm-updater/1' "$API_URL")" || die 'could not read the latest GitHub release metadata'
tag="$(printf '%s' "$metadata" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$tag" ] || die 'GitHub metadata did not contain tag_name'
case "$tag" in v[0-9]*) ;; *) die "unexpected release tag: $tag" ;; esac
compact="${tag#v}"
compact="${compact//./}"
archive="termux-ath9k-vm-v${compact}-update.tar.gz"
checksum="${archive}.sha256"
base_url="https://github.com/$REPO/releases/download/$tag"

if [ "$CHECK_ONLY" -eq 1 ]; then
  printf 'Latest release: %s\n' "$tag"
  printf 'Update archive: %s\n' "$archive"
  printf 'Project: %s\n' "$PROJECT_DIR"
  printf 'Persistent data: %s\n' "$STATE_DIR"
  printf 'No files were downloaded or changed.\n'
  exit 0
fi

if [ "$KEEP_OLD" -eq 0 ] && [ "$YES" -eq 0 ]; then
  read -r -p "Update $PROJECT_DIR and remove the old checkout after success? [y/N]: " answer
  case "${answer:-n}" in [Yy]|[Yy][Ee][Ss]) ;; *) die 'update cancelled; no files were changed' ;; esac
fi

mkdir -p "$(dirname -- "$PROJECT_DIR")"
TMP_ROOT="$(mktemp -d "$(dirname -- "$PROJECT_DIR")/.awvm-update.XXXXXX")"
say "Downloading $archive"
curl -fL --retry 3 --connect-timeout 15 --max-time 180 \
  -A 'awvm-updater/1' "$base_url/$archive" -o "$TMP_ROOT/$archive"
curl -fL --retry 3 --connect-timeout 15 --max-time 60 \
  -A 'awvm-updater/1' "$base_url/$checksum" -o "$TMP_ROOT/$checksum"

say 'Verifying SHA-256 before extraction'
(
  cd "$TMP_ROOT"
  sha256sum -c "$checksum"
)
validate_archive_paths "$TMP_ROOT/$archive"

say 'Extracting the verified update archive'
mkdir -p "$TMP_ROOT/extracted"
tar --extract --gzip --file "$TMP_ROOT/$archive" --directory "$TMP_ROOT/extracted" --no-same-owner --no-same-permissions --no-overwrite-dir
staged_root="$TMP_ROOT/extracted/termux-ath9k-vm-full-lite"
[ -f "$staged_root/bin/install-termux.sh" ] || die 'Verified update archive has an unexpected layout.'

say 'Running the project installer while the old checkout remains available'
export VM_STATE_ROOT="$STATE_DIR"
export VM_LEGACY_DIR="$PROJECT_DIR"
bash "$staged_root/bin/install-termux.sh"

# Keep a recoverable old checkout until the staged tree has been moved into its
# final place. This is important when the updater replaces itself in-place.
old_backup=""
if [ "$KEEP_OLD" -eq 1 ]; then
  old_backup="$PROJECT_DIR.old-$tag-$(date -u '+%Y%m%dT%H%M%SZ')"
  [ ! -e "$old_backup" ] || die "old-checkout backup path already exists: $old_backup"
else
  old_slot="$(mktemp -d "$(dirname -- "$PROJECT_DIR")/.$(basename -- "$PROJECT_DIR").old.XXXXXX")"
  old_backup="$old_slot/checkout"
fi
say "Moving the current checkout aside temporarily"
mv -- "$PROJECT_DIR" "$old_backup"
if ! mv -- "$staged_root" "$PROJECT_DIR"; then
  warn 'could not install the new checkout; restoring the old checkout'
  mv -- "$old_backup" "$PROJECT_DIR" || warn "manual recovery may be required from $old_backup"
  [ "$KEEP_OLD" -eq 1 ] || rm -rf -- "$(dirname -- "$old_backup")"
  die 'update failed while replacing the checkout'
fi

if [ "$KEEP_OLD" -eq 0 ] && [ "$CWD_IN_PROJECT" -eq 0 ]; then
  say "Removing the old checkout after successful replacement"
  if [ -n "${old_slot:-}" ]; then
    rm -rf -- "$old_slot"
  else
    rm -rf -- "$old_backup"
  fi
else
  if [ "$KEEP_OLD" -eq 1 ]; then
    printf 'Old checkout kept at: %s\n' "$old_backup"
  else
    printf 'Old checkout kept at: %s\n' "$old_backup"
    printf 'It was retained because the updater was started inside the old checkout; run: cd %s\n' "$PROJECT_DIR"
  fi
fi

[ -x "$PROJECT_DIR/bin/awvm-update.sh" ] || die 'update completed without the bundled updater'
[ -x "$PROJECT_DIR/bin/vm-launcher.sh" ] || die 'update completed without vm-launcher.sh'
[ -x "$PROJECT_DIR/bin/vmctl.sh" ] || die 'update completed without vmctl.sh'
VM_STATE_ROOT="$STATE_DIR" "$PROJECT_DIR/bin/vm-launcher.sh" --lite --dry-run --non-interactive >/dev/null
VM_STATE_ROOT="$STATE_DIR" "$PROJECT_DIR/bin/vm-launcher.sh" --full --dry-run --non-interactive >/dev/null

printf '\nUpdate completed successfully.\n'
printf 'Project: %s\n' "$PROJECT_DIR"
printf 'Persistent VM data: %s\n' "$STATE_DIR"
printf 'Start the VM with:\n  bash %s/bin/vm-launcher.sh\n' "$PROJECT_DIR"
