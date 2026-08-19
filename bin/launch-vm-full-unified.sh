#!/data/data/com.termux/files/usr/bin/bash
# Unified-release Full adapter. The nested Full v0.3.0 files remain untouched.
# This adapter adds the unified launcher's Android RTC and optional-network policy.
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VM_DIR="${VM_DIR:-$BASE_DIR/full}"
DISK="${DISK:-$VM_DIR/guest/alpine-ath9k.img}"
KERNEL="${KERNEL:-$VM_DIR/guest/vmlinuz-lts}"
INITRD="${INITRD:-$VM_DIR/guest/initramfs-lts}"
RAM="${RAM:-768}"
SMP="${SMP:-1}"
SSH_PORT="${SSH_PORT:-2222}"
MONITOR="${MONITOR:-$VM_DIR/qemu-unified-full-monitor.sock}"
SHARE_DIR="${SHARE_DIR:-$HOME}"
USB_MODE="${USB_MODE:-none}"
USB_REDIRECT_PORT="${USB_REDIRECT_PORT:-23456}"
SERIAL_MODE="${SERIAL_MODE:-stdio}"
CONSOLE_SOCKET="${CONSOLE_SOCKET:-$VM_DIR/qemu-unified-full-console.sock}"
PIDFILE="${PIDFILE:-}"
TCG_THREAD="${TCG_THREAD:-auto}"
# Direct use of this adapter preserves Full's historical online behavior; the
# unified dispatcher always supplies an explicit 0/1 choice after prompting.
ENABLE_NET="${ENABLE_NET:-1}"
AUTH_MODE="${AUTH_MODE:-root-console}"
RTC_BASE="${RTC_BASE:-$(date -u '+%Y-%m-%dT%H:%M:%S')}"
TIME_SYNC="${TIME_SYNC:-1}"
TIME_SYNC_MARKER="${TIME_SYNC_MARKER:-$CONSOLE_SOCKET.timesync-ready}"
ATTACH_AFTER_SYNC=0
if [ "$TIME_SYNC" = 1 ] && [ "$SERIAL_MODE" = stdio ]; then
  SERIAL_MODE=unix
  ATTACH_AFTER_SYNC=1
fi
QEMU="${QEMU:-qemu-system-aarch64}"

[ -f "$DISK" ] || { echo "missing disk: $DISK" >&2; exit 1; }
[ -f "$KERNEL" ] || { echo "missing kernel: $KERNEL" >&2; exit 1; }
[ -f "$INITRD" ] || { echo "missing initramfs: $INITRD" >&2; exit 1; }
command -v "$QEMU" >/dev/null || { echo "missing $QEMU; install qemu-system-aarch64-headless" >&2; exit 1; }
case "$TCG_THREAD" in
  auto) [ "$SMP" -eq 1 ] && TCG_THREAD=single || TCG_THREAD=multi ;;
  single|multi) ;;
  *) echo 'TCG_THREAD must be auto, single, or multi' >&2; exit 2 ;;
esac
case "$ENABLE_NET" in 0|1) ;; *) echo 'ENABLE_NET must be 0 or 1' >&2; exit 2 ;; esac
case "$AUTH_MODE" in root-console|login|login-empty) ;; *) echo 'AUTH_MODE must be root-console, login, or login-empty' >&2; exit 2 ;; esac
configure_auth(){
  local helper="$BASE_DIR/src/configure-console-auth.sh" current expected
  [ -x "$helper" ] || { echo "missing auth helper: $helper" >&2; exit 1; }
  current="$(debugfs -R 'cat /etc/inittab' "$DISK" 2>/dev/null || true)"
  case "$AUTH_MODE" in
    root-console) expected='ttyAMA0::respawn:/bin/sh -l' ;;
    login|login-empty) expected='ttyAMA0::respawn:/sbin/getty -L 0 ttyAMA0 vt100' ;;
  esac
  if [ "$AUTH_MODE" = login-empty ] || ! printf '%s\n' "$current" | grep -qxF "$expected"; then
    "$helper" "$DISK" "$AUTH_MODE"
  fi
}
configure_auth
case "$SERIAL_MODE" in
  stdio) SERIAL_ARGS=(-serial mon:stdio) ;;
  unix) rm -f "$CONSOLE_SOCKET"; SERIAL_ARGS=(-chardev "socket,id=serial0,path=$CONSOLE_SOCKET,server=on,wait=off" -serial chardev:serial0) ;;
  *) echo 'SERIAL_MODE must be stdio or unix' >&2; exit 2 ;;
esac

mkdir -p "$VM_DIR/run"
[ ! -S "$MONITOR" ] || { echo "refusing to replace active/stale monitor socket: $MONITOR" >&2; exit 1; }
rm -f "$MONITOR"

ARGS=(
  -machine virt
  -accel "tcg,thread=$TCG_THREAD"
  -cpu max
  -m "${RAM}M"
  -smp "$SMP"
  -kernel "$KERNEL"
  -initrd "$INITRD"
  -append 'console=ttyAMA0,115200 root=/dev/vda rw rootflags=rw rootfstype=ext4 rootwait'
  -drive "if=none,id=rootdisk,format=raw,file=$DISK,cache=writeback"
  -device virtio-blk-pci,drive=rootdisk
  -device virtio-rng-pci
  -device qemu-xhci,id=xhci
  -rtc "base=$RTC_BASE"
  -virtfs "local,security_model=none,id=termux,mount_tag=termux,path=$SHARE_DIR"
  -display none
  -monitor "unix:$MONITOR,server,nowait"
  "${SERIAL_ARGS[@]}"
)
if [ -n "$PIDFILE" ]; then ARGS+=( -pidfile "$PIDFILE" ); fi
if [ "$ENABLE_NET" = 1 ]; then
  ARGS+=( -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" -device virtio-net-pci,netdev=net0 )
fi
case "$USB_MODE" in
  none) ;;
  direct)
    [ -n "${TERMUX_USB_FD:-}" ] || { echo 'USB_MODE=direct requires TERMUX_USB_FD from termux-usb -E -e.' >&2; exit 1; }
    ARGS+=( -device usb-host,vendorid=0x0cf3,productid=0x9271,bus=xhci.0 )
    ;;
  redir)
    ARGS+=( -chardev "socket,host=127.0.0.1,port=$USB_REDIRECT_PORT,id=usbredirchardev1" )
    ARGS+=( -device usb-redir,chardev=usbredirchardev1,id=usbredirdev1,debug=2 )
    ;;
  *) echo 'USB_MODE must be none, direct, or redir' >&2; exit 2 ;;
esac

echo "Full VM adapter: ram=${RAM}M smp=$SMP tcg=$TCG_THREAD usb=$USB_MODE net=$ENABLE_NET auth=$AUTH_MODE rtc=$RTC_BASE time_sync=$TIME_SYNC" >&2

if [ "$TIME_SYNC" = 1 ] && [ "$SERIAL_MODE" = unix ]; then
  command -v socat >/dev/null || { echo 'TIME_SYNC=1 requires socat.' >&2; exit 1; }
  rm -f "$TIME_SYNC_MARKER" "$CONSOLE_SOCKET.time-sync-capture"
  "$QEMU" "${ARGS[@]}" &
  QEMU_PID=$!
  for _ in $(seq 1 60); do
    [ -S "$CONSOLE_SOCKET" ] && break
    kill -0 "$QEMU_PID" 2>/dev/null || { wait "$QEMU_PID" || true; exit 1; }
    sleep 0.25
  done
  [ -S "$CONSOLE_SOCKET" ] || { kill "$QEMU_PID" 2>/dev/null || true; wait "$QEMU_PID" 2>/dev/null || true; echo 'Timed out waiting for serial console for time sync.' >&2; exit 1; }
  socat -u "UNIX-CONNECT:$CONSOLE_SOCKET" - >"$CONSOLE_SOCKET.time-sync-capture" 2>/dev/null &
  CONSOLE_READER=$!
  PROMPT_SEEN=0
  for _ in $(seq 1 120); do
    if grep -aEq '^[^#]*#[[:space:]]' "$CONSOLE_SOCKET.time-sync-capture" 2>/dev/null; then PROMPT_SEEN=1; break; fi
    kill -0 "$QEMU_PID" 2>/dev/null || break
    sleep 0.25
  done
  kill "$CONSOLE_READER" 2>/dev/null || true
  wait "$CONSOLE_READER" 2>/dev/null || true
  SYNC_DATE="${RTC_BASE/T/ }"
  printf "date -u -s '%s'\n" "$SYNC_DATE" | socat - "UNIX-CONNECT:$CONSOLE_SOCKET" >/dev/null 2>&1 || true
  touch "$TIME_SYNC_MARKER"
  if [ "$ATTACH_AFTER_SYNC" = 1 ]; then
    socat -,raw,echo=0 "UNIX-CONNECT:$CONSOLE_SOCKET" || true
  fi
  wait "$QEMU_PID"
else
  exec "$QEMU" "${ARGS[@]}"
fi

