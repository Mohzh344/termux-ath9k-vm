#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VM_DIR="${VM_DIR:-$BASE_DIR}"
DISK="${DISK:-$VM_DIR/guest/alpine-ath9k.img}"
KERNEL="${KERNEL:-$VM_DIR/guest/vmlinuz-lts}"
INITRD="${INITRD:-$VM_DIR/guest/initramfs-lts}"
RAM="${RAM:-768}"
SMP="${SMP:-1}"
SSH_PORT="${SSH_PORT:-2222}"
MONITOR="${MONITOR:-$VM_DIR/qemu-monitor.sock}"
SHARE_DIR="${SHARE_DIR:-$HOME}"
USB_MODE="${USB_MODE:-none}"
USB_REDIRECT_PORT="${USB_REDIRECT_PORT:-23456}"
SERIAL_MODE="${SERIAL_MODE:-stdio}"
CONSOLE_SOCKET="${CONSOLE_SOCKET:-$VM_DIR/qemu-console.sock}"
PIDFILE="${PIDFILE:-}"
TCG_THREAD="${TCG_THREAD:-auto}"

QEMU="${QEMU:-qemu-system-aarch64}"
[ -x "$DISK" ] || [ -f "$DISK" ] || { echo "missing disk: $DISK" >&2; exit 1; }
[ -f "$KERNEL" ] || { echo "missing kernel: $KERNEL" >&2; exit 1; }
[ -f "$INITRD" ] || { echo "missing initramfs: $INITRD" >&2; exit 1; }
command -v "$QEMU" >/dev/null || { echo "missing $QEMU; install the Termux qemu-system-aarch64-headless package" >&2; exit 1; }

mkdir -p "$VM_DIR/run"
if [ -S "$MONITOR" ]; then
  echo "refusing to replace active/stale monitor socket: $MONITOR" >&2
  echo "stop the existing VM first; remove the socket manually only after confirming it is stale" >&2
  exit 1
fi
rm -f "$MONITOR"
case "$SERIAL_MODE" in
  unix) rm -f "$CONSOLE_SOCKET" ;;
  stdio) ;;
  *) echo "SERIAL_MODE must be stdio or unix" >&2; exit 2 ;;
esac

# TCG is mandatory on rootless Android. A single virtual CPU avoids costly
# inter-vCPU synchronization during boot; multi-thread TCG is only used when requested SMP > 1.
case "$TCG_THREAD" in
  auto) [ "$SMP" -eq 1 ] && TCG_THREAD=single || TCG_THREAD=multi ;;
  single|multi) ;;
  *) echo "TCG_THREAD must be auto, single, or multi" >&2; exit 2 ;;
esac
# The guest kernel has the virtio and XHCI support needed by this command line.
ARGS=(

  -machine virt
  -accel "tcg,thread=$TCG_THREAD"
  -cpu max
  -m "$RAM"M
  -smp "$SMP"
  -kernel "$KERNEL"
  -initrd "$INITRD"
  -append "console=ttyAMA0,115200 root=/dev/vda rw rootflags=rw rootfstype=ext4 rootwait"
  -drive "if=none,id=rootdisk,format=raw,file=$DISK,cache=writeback"
  -device virtio-blk-pci,drive=rootdisk
  -device virtio-rng-pci
  -device qemu-xhci,id=xhci
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22"
  -device virtio-net-pci,netdev=net0
  -virtfs "local,security_model=none,id=termux,mount_tag=termux,path=$SHARE_DIR"
  -display none
  -monitor "unix:$MONITOR,server,nowait"
)

if [ -n "$PIDFILE" ]; then
  ARGS+=( -pidfile "$PIDFILE" )
fi

case "$SERIAL_MODE" in
  stdio)
    # Normal no-USB mode: guest serial plus QEMU monitor on this terminal.
    ARGS+=( -serial mon:stdio )
    ;;
  unix)
    # USB permission is held by termux-usb, which owns child stdio.  Publish
    # only the guest UART on a private Unix socket, then attach via socat.
    ARGS+=( -chardev "socket,id=serial0,path=$CONSOLE_SOCKET,server=on,wait=off" )
    ARGS+=( -serial chardev:serial0 )
    ;;
esac

case "$USB_MODE" in
  none)
    ;;
  direct)
    # This mode must be launched through termux-usb -e so TERMUX_USB_FD is inherited.
    # The Termux libusb patch exposes the Android-granted fd to QEMU's libusb backend.
    ARGS+=( -device usb-host,vendorid=0x0cf3,productid=0x9271,bus=xhci.0 )
    ;;
  redir)
    # The companion usb-attach-redir.sh starts usbredirect separately and connects this VM
    # to it over localhost. The guest then sees an ordinary USB device.
    ARGS+=( -chardev "socket,host=127.0.0.1,port=$USB_REDIRECT_PORT,id=usbredirchardev1" )
    ARGS+=( -device usb-redir,chardev=usbredirchardev1,id=usbredirdev1,debug=2 )
    ;;
  *)
    echo "USB_MODE must be none, direct, or redir" >&2
    exit 2
    ;;
esac

exec "$QEMU" "${ARGS[@]}"
