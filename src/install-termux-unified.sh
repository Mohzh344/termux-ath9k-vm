#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v pkg >/dev/null 2>&1 || { echo 'Run this installer inside Termux.' >&2; exit 1; }
printf 'Installing host dependencies for the combined Full + Lite bundle...\n'
pkg update -y
pkg install -y qemu-system-aarch64-headless termux-api socat e2fsprogs
find "$BASE_DIR/bin" "$BASE_DIR/full/bin" "$BASE_DIR/lite/bin" -type f -name '*.sh' -exec chmod +x {} +
printf '\nInstallation complete. Recommended launcher:\n  %s/bin/vm-launcher.sh\n\nThe nested Full and Lite launchers remain available for advanced/manual use.\n' "$BASE_DIR"
