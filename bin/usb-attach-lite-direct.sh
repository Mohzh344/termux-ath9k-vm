#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_PATH="${1:-}"
[ -n "$DEVICE_PATH" ] || { echo "Usage: $0 /dev/bus/usb/BBB/DDD" >&2; exit 2; }
command -v termux-usb >/dev/null || { echo 'Termux:API is required for termux-usb' >&2; exit 1; }
termux-usb -r "$DEVICE_PATH" >/dev/null
echo "Lite console: $BASE_DIR/qemu-lite-console.sock" >&2
exec termux-usb -E -e "$BASE_DIR/bin/qemu-lite-direct-inner.sh" "$DEVICE_PATH"
