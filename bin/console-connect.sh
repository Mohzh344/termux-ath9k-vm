#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOCKET="${CONSOLE_SOCKET:-$BASE_DIR/qemu-console.sock}"
command -v socat >/dev/null || { echo 'Install socat first: pkg install socat' >&2; exit 1; }
[ -S "$SOCKET" ] || { echo "VM serial socket is not ready: $SOCKET" >&2; exit 1; }
exec socat -,raw,echo=0 "UNIX-CONNECT:$SOCKET"
