#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${TERMUX_USB_FD:-}" ]; then
  echo 'TERMUX_USB_FD is missing. This wrapper must be launched by termux-usb -E -e.' >&2
  exit 1
fi
export USB_MODE=direct
exec "$BASE_DIR/bin/launch-vm.sh" "$@"
