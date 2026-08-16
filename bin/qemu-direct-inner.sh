#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${TERMUX_USB_FD:-}" ]; then
  echo 'TERMUX_USB_FD is missing. This wrapper must be launched by termux-usb -E -e.' >&2
  exit 1
fi
export USB_MODE=direct
# termux-usb owns stdio while it holds Android's USB permission.  A socket
# console keeps the VM interactive from a second Termux session.
export SERIAL_MODE=unix
export CONSOLE_SOCKET="${CONSOLE_SOCKET:-$BASE_DIR/qemu-console.sock}"
exec "$BASE_DIR/bin/launch-vm.sh" "$@"
