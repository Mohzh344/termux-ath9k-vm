#!/usr/bin/env bash
set -Eeuo pipefail

REPO="Mohzh344/android-wifi-monitor-injection-rootless"
API_URL="https://api.github.com/repos/$REPO/releases/latest"
PROJECT_DIR="${AWVM_PROJECT_DIR:-${HOME:?}/awvm}"
if [ -n "${VM_STATE_ROOT:-}" ]; then
  STATE_DIR="$VM_STATE_ROOT"
elif [ -n "${XDG_DATA_HOME:-}" ] && [ -d "$XDG_DATA_HOME/android-wifi-monitor-injection-rootless" ]; then
  STATE_DIR="$XDG_DATA_HOME/android-wifi-monitor-injection-rootless"
elif [ -z "${XDG_DATA_HOME:-}" ] && [ -d "${HOME:?}/.local/share/android-wifi-monitor-injection-rootless" ]; then
  STATE_DIR="$HOME/.local/share/android-wifi-monitor-injection-rootless"
elif [ -n "${XDG_DATA_HOME:-}" ]; then
  STATE_DIR="$XDG_DATA_HOME/awvm"
else
  STATE_DIR="$HOME/.local/share/awvm"
fi
TMP_ROOT=""

say(){ printf '\n==> %s\n' "$*"; }
die(){ printf '\nERROR: %s\n' "$*" >&2; exit 1; }
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

case "$PROJECT_DIR" in
  /|"$HOME"|"$HOME/"|"$HOME/.local"|"$HOME/.local/share") die "refusing unsafe project directory: $PROJECT_DIR" ;;
esac
[ -e "$PROJECT_DIR" ] && die "project directory already exists: $PROJECT_DIR (use bin/awvm-update.sh for an existing installation)"
case "$STATE_DIR/" in
  "$PROJECT_DIR/"*) die "VM_STATE_ROOT must be outside the project directory: $STATE_DIR" ;;
esac

command -v pkg >/dev/null 2>&1 || die 'Run this installer inside Termux (pkg was not found).'
say 'Installing bootstrap dependencies'
pkg update -y
pkg install -y curl tar coreutils
command -v curl >/dev/null 2>&1 || die 'curl is required after bootstrap installation.'
command -v tar >/dev/null 2>&1 || die 'tar is required after bootstrap installation.'
command -v sha256sum >/dev/null 2>&1 || die 'sha256sum is required; install coreutils.'

say 'Reading the latest GitHub release'
metadata="$(curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 \
  -H 'Accept: application/vnd.github+json' -A 'awvm-installer/1' "$API_URL")"
tag="$(printf '%s' "$metadata" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$tag" ] || die 'Could not read tag_name from GitHub release metadata.'
case "$tag" in v[0-9]*) ;; *) die "Unexpected release tag: $tag" ;; esac
compact="${tag#v}"
compact="${compact//./}"
archive="termux-ath9k-vm-v${compact}-full-lite-ready.tar.gz"
checksum="${archive}.sha256"
base_url="https://github.com/$REPO/releases/download/$tag"

printf 'Selected release: %s\n' "$tag"
printf 'Project directory: %s\n' "$PROJECT_DIR"
printf 'Persistent VM data: %s\n' "$STATE_DIR"

mkdir -p "$(dirname "$PROJECT_DIR")"
TMP_ROOT="$(mktemp -d "$(dirname "$PROJECT_DIR")/.awvm-install.XXXXXX")"
say "Downloading $archive"
curl -fL --retry 3 --connect-timeout 15 --max-time 180 \
  -A 'awvm-installer/1' "$base_url/$archive" -o "$TMP_ROOT/$archive"
curl -fL --retry 3 --connect-timeout 15 --max-time 60 \
  -A 'awvm-installer/1' "$base_url/$checksum" -o "$TMP_ROOT/$checksum"

say 'Verifying SHA-256 before extraction'
(
  cd "$TMP_ROOT"
  sha256sum -c "$checksum"
)
validate_archive_paths "$TMP_ROOT/$archive"

say 'Extracting the verified archive'
mkdir -p "$TMP_ROOT/extracted"
tar --extract --gzip --file "$TMP_ROOT/$archive" --directory "$TMP_ROOT/extracted" --no-same-owner --no-same-permissions --no-overwrite-dir
staged_root="$TMP_ROOT/extracted/termux-ath9k-vm-full-lite"
[ -f "$staged_root/bin/install-termux.sh" ] || die 'Verified archive has an unexpected layout.'

say 'Installing the VM and adopting persistent data'
export VM_STATE_ROOT="$STATE_DIR"
bash "$staged_root/bin/install-termux.sh"

# The installer has completed and any bundled images have been adopted. Only now
# is the new project moved into its final short directory.
mkdir -p "$(dirname "$PROJECT_DIR")"
mv -- "$staged_root" "$PROJECT_DIR"

[ -x "$PROJECT_DIR/bin/vm-launcher.sh" ] || die 'Installation completed without vm-launcher.sh.'
[ -x "$PROJECT_DIR/bin/vmctl.sh" ] || die 'Installation completed without vmctl.sh.'
printf '\nInstallation completed successfully.\n'
printf 'Enter the project with:\n  cd %s\n' "$PROJECT_DIR"
printf 'Start the VM with:\n  bash %s/bin/vm-launcher.sh\n' "$PROJECT_DIR"
printf 'Check the installation with:\n  bash %s/bin/vmctl.sh doctor\n' "$PROJECT_DIR"
