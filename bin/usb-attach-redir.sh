#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_PATH="${1:-}"
USBREDIRECT="${USBREDIRECT:-$HOME/.local/bin/usbredirect}"
PORT="${USB_REDIRECT_PORT:-23456}"

if [ -z "$DEVICE_PATH" ]; then
  echo "Usage: USBREDIRECT=/path/to/usbredirect $0 /dev/bus/usb/BBB/DDD" >&2
  exit 2
fi
[ -x "$USBREDIRECT" ] || { echo "missing executable usbredirect: $USBREDIRECT" >&2; exit 1; }
command -v termux-usb >/dev/null || { echo 'termux-api package is required' >&2; exit 1; }
termux-usb -r "$DEVICE_PATH" >/dev/null

# usbredirect must be a Termux-aware build that accepts the fd supplied by termux-usb.
# It exposes the device as a USB redirection stream to QEMU.
termux-usb -e "$USBREDIRECT --device $DEVICE_PATH --as 127.0.0.1:$PORT" "$DEVICE_PATH" &
REDIR_PID=$!
cleanup() { kill "$REDIR_PID" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
sleep 1
USB_MODE=redir USB_REDIRECT_PORT="$PORT" "$BASE_DIR/bin/launch-vm.sh"
