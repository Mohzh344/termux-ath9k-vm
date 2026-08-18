#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${LOG_DIR:-$PROJECT_DIR/benchmarks/kernel-boot-logs}"
QEMU="${QEMU:-qemu-system-aarch64}"
RAM="${RAM:-768}"
SMP="${SMP:-2}"
TIMEOUT="${TIMEOUT:-100}"
DISK="${DISK:-$PROJECT_DIR/guest/alpine-ath9k-v030-lite.img}"
KERNELS="${KERNELS:-lts tiny safe}"
mkdir -p "$LOG_DIR"

required=(
  CONFIG_CFG80211 CONFIG_MAC80211 CONFIG_ATH_COMMON CONFIG_ATH9K_HW
  CONFIG_ATH9K_COMMON CONFIG_ATH9K_HTC CONFIG_USB_XHCI_HCD CONFIG_VIRTIO_BLK
  CONFIG_EXT4_FS CONFIG_PACKET CONFIG_FW_LOADER CONFIG_FW_LOADER_COMPRESS_ZSTD
)

fail=0
for tier in $KERNELS; do
  kernel="$PROJECT_DIR/guest/vmlinuz-$tier"
  config="$PROJECT_DIR/docs/kernel-$tier.config"
  [ -f "$kernel" ] || { echo "FAIL $tier: missing $kernel"; fail=1; continue; }
  if [ "$tier" != lts ]; then
    [ -f "$config" ] || { echo "FAIL $tier: missing $config"; fail=1; continue; }
    for sym in "${required[@]}"; do
      grep -q "^${sym}=y$" "$config" || { echo "FAIL $tier: $sym is not built-in"; fail=1; }
    done
  fi
  log="$LOG_DIR/$tier.log"
  set +e
  qemu_args=(
    -machine virt -cpu max -m "${RAM}M" -smp "$SMP"
    -kernel "$kernel"
    -append 'console=ttyAMA0,115200 root=/dev/vda rw rootflags=rw rootfstype=ext4 rootwait'
    -drive "if=none,id=rootdisk,format=raw,file=$DISK,cache=writeback"
  )
  if [ "$tier" = lts ]; then
    qemu_args+=( -initrd "$PROJECT_DIR/guest/initramfs-lts" )
  fi
  timeout "$TIMEOUT" "$QEMU" "${qemu_args[@]}" \
    -device virtio-blk-pci,drive=rootdisk -device virtio-rng-pci -device qemu-xhci,id=xhci \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 -nographic -monitor none \
    -serial "file:$log" >/dev/null 2>&1
  rc=$?
  set -e
  root_ok=0; openrc_ok=0; init_ok=0
  grep -qE 'Alpine Init|Run /sbin/init as init process|Run /init as init process' "$log" && init_ok=1 || true
  grep -qE 'Mounting root: ok|VFS: Mounted root' "$log" && root_ok=1 || true
  grep -q 'OpenRC .*starting' "$log" && openrc_ok=1 || true
  if [ "$init_ok" = 1 ] && [ "$root_ok" = 1 ] && [ "$openrc_ok" = 1 ]; then
    echo "PASS $tier: init=$init_ok root=$root_ok openrc=$openrc_ok qemu_rc=$rc (124 means timeout while VM remains running)"
  else
    echo "FAIL $tier: init=$init_ok root=$root_ok openrc=$openrc_ok qemu_rc=$rc log=$log"
    fail=1
  fi
done
exit "$fail"
