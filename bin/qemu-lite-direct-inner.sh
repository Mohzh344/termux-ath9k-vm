#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
[ -n "${TERMUX_USB_FD:-}" ] || { echo 'TERMUX_USB_FD is missing; launch through termux-usb -E -e.' >&2; exit 1; }
export USB_MODE=direct
export SERIAL_MODE=unix
export CONSOLE_SOCKET="${CONSOLE_SOCKET:-$BASE_DIR/qemu-lite-console.sock}"
exec "$BASE_DIR/bin/launch-vm-lite.sh" "$@"
