#!/bin/sh
set -eu
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${LOG:-$BASE_DIR/boot-test.log}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-420}"
set +e
timeout "${BOOT_TIMEOUT}s" qemu-system-aarch64 \
  -machine virt -accel tcg,thread=single -cpu max -m 768M -smp 1 \
  -kernel "$BASE_DIR/guest/vmlinuz-lts" \
  -initrd "$BASE_DIR/guest/initramfs-lts" \
  -append 'console=ttyAMA0,115200 root=/dev/vda rw rootfstype=ext4 rootwait' \
  -drive "if=none,id=rootdisk,format=raw,file=$BASE_DIR/guest/alpine-ath9k.img,cache=writeback" \
  -device virtio-blk-pci,drive=rootdisk \
  -device virtio-rng-pci \
  -device qemu-xhci,id=xhci \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -nographic -monitor none -serial "file:$LOG"
status=$?
printf 'qemu_exit=%s\n' "$status"
tail -n 80 "$LOG"
if grep -qE 'Mounting root: ok|Alpine Init|OpenRC .* is starting|login:' "$LOG"; then
  echo 'BOOT_OK: guest kernel and root disk reached Alpine init/OpenRC'
  exit 0
fi
echo 'BOOT_NOT_CONFIRMED: inspect boot-test.log' >&2
exit 1
