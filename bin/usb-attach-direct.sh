#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_PATH="${1:-}"
if [ -z "$DEVICE_PATH" ]; then
  echo "Usage: $0 /dev/bus/usb/BBB/DDD" >&2
  echo "Find the device with: termux-usb -l" >&2
  exit 2
fi

command -v termux-usb >/dev/null || { echo 'termux-api package is required for termux-usb' >&2; exit 1; }
termux-usb -r "$DEVICE_PATH" >/dev/null
# -E exports the Android UsbDeviceConnection fd as TERMUX_USB_FD.
# QEMU runs with a Unix serial socket because termux-usb retains child stdio.
echo "The interactive guest console will be at: $BASE_DIR/qemu-console.sock" >&2
echo "Open a SECOND Termux session and run: $BASE_DIR/bin/console-connect.sh" >&2
# The inner launcher inherits it and QEMU's Termux-patched libusb sees one device.
exec termux-usb -E -e "$BASE_DIR/bin/qemu-direct-inner.sh" "$DEVICE_PATH"
