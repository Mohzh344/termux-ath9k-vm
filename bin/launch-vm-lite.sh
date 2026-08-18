#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${PROFILE:-wifi-only}"
KERNEL_TIER="${KERNEL_TIER:-safe}"
IMAGE_VARIANT="lite"
DISK="${DISK:-$BASE_DIR/guest/alpine-ath9k-v030-lite.img}"
RAM="${RAM:-}"
SMP="${SMP:-}"
CPU_MODEL="${CPU_MODEL:-max}"
TCG_THREAD="${TCG_THREAD:-multi}"
USB_MODE="${USB_MODE:-none}"
USB_REDIRECT_PORT="${USB_REDIRECT_PORT:-23456}"
SERIAL_MODE="${SERIAL_MODE:-stdio}"
CONSOLE_SOCKET="${CONSOLE_SOCKET:-$BASE_DIR/qemu-lite-console.sock}"
MONITOR="${MONITOR:-$BASE_DIR/qemu-lite-monitor.sock}"
PIDFILE="${PIDFILE:-}"
ENABLE_NET="${ENABLE_NET:-0}"
SHARE_MODE="${SHARE_MODE:-none}"
SHARE_DIR="${SHARE_DIR:-$HOME}"
QEMU="${QEMU:-qemu-system-aarch64}"

case "$PROFILE" in
  wifi-only) : "${RAM:=512}"; : "${SMP:=1}"; ENABLE_NET="${ENABLE_NET:-0}"; SHARE_MODE="${SHARE_MODE:-none}" ;;
  balanced) : "${RAM:=768}"; : "${SMP:=2}" ;;
  default) : "${RAM:=1024}"; : "${SMP:=2}" ;;
  legacy) : "${RAM:=1536}"; : "${SMP:=4}" ;;
  *) echo 'PROFILE must be wifi-only, balanced, default, or legacy' >&2; exit 2 ;;
esac

case "$KERNEL_TIER" in
  tiny|safe)
    KERNEL="$BASE_DIR/guest/vmlinuz-$KERNEL_TIER"
    INITRD=""
    ;;
  lts)
    KERNEL="$BASE_DIR/guest/vmlinuz-lts-lite"
    INITRD="$BASE_DIR/guest/initramfs-lts-lite"
    ;;
  *) echo 'KERNEL_TIER must be tiny, safe, or lts' >&2; exit 2 ;;
esac

[ -f "$DISK" ] || { echo "missing disk: $DISK" >&2; exit 1; }
[ -f "$KERNEL" ] || { echo "missing kernel: $KERNEL" >&2; exit 1; }
[ -z "$INITRD" ] || [ -f "$INITRD" ] || { echo "missing initramfs: $INITRD" >&2; exit 1; }
command -v "$QEMU" >/dev/null || { echo "missing $QEMU" >&2; exit 1; }
case "$TCG_THREAD" in single|multi) ;; *) echo 'TCG_THREAD must be single or multi' >&2; exit 2 ;; esac
case "$SERIAL_MODE" in stdio) SERIAL_ARGS=(-serial mon:stdio) ;; unix) rm -f "$CONSOLE_SOCKET"; SERIAL_ARGS=(-chardev "socket,id=serial0,path=$CONSOLE_SOCKET,server=on,wait=off" -serial chardev:serial0) ;; *) echo 'SERIAL_MODE must be stdio or unix' >&2; exit 2 ;; esac

ARGS=(
  -machine virt
  -accel "tcg,thread=$TCG_THREAD"
  -cpu "$CPU_MODEL"
  -m "${RAM}M"
  -smp "$SMP"
  -kernel "$KERNEL"
  -append 'console=ttyAMA0,115200 root=/dev/vda rw rootfstype=ext4 rootflags=rw rootwait'
  -drive "if=none,id=rootdisk,format=raw,file=$DISK,cache=writeback"
  -device virtio-blk-pci,drive=rootdisk
  -device virtio-rng-pci
  -device qemu-xhci,id=xhci
  -display none
  -monitor "unix:$MONITOR,server,nowait"
  "${SERIAL_ARGS[@]}"
)
if [ -n "$INITRD" ]; then ARGS+=( -initrd "$INITRD" ); fi
if [ -n "$PIDFILE" ]; then ARGS+=( -pidfile "$PIDFILE" ); fi
if [ "$ENABLE_NET" = 1 ]; then
  ARGS+=( -netdev "user,id=net0" -device virtio-net-pci,netdev=net0 )
fi
if [ "$SHARE_MODE" = 9p ]; then
  ARGS+=( -virtfs "local,security_model=none,id=termux,mount_tag=termux,path=$SHARE_DIR" )
elif [ "$SHARE_MODE" != none ]; then
  echo 'SHARE_MODE must be none or 9p' >&2; exit 2
fi
case "$USB_MODE" in
  none) ;;
  direct) ARGS+=( -device usb-host,vendorid=0x0cf3,productid=0x9271,bus=xhci.0 ) ;;
  redir)
    ARGS+=( -chardev "socket,host=127.0.0.1,port=$USB_REDIRECT_PORT,id=usbredirchardev1" )
    ARGS+=( -device usb-redir,chardev=usbredirchardev1,id=usbredirdev1,debug=2 )
    ;;
  *) echo 'USB_MODE must be none, direct, or redir' >&2; exit 2 ;;
esac

echo "Lite VM: profile=$PROFILE tier=$KERNEL_TIER ram=${RAM}M smp=$SMP cpu=$CPU_MODEL tcg=$TCG_THREAD usb=$USB_MODE net=$ENABLE_NET share=$SHARE_MODE" >&2
exec "$QEMU" "${ARGS[@]}"
