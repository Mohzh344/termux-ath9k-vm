#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${KERNEL_SRC:-$PROJECT_DIR/kernel/linux-6.18}"
OUT_ROOT="${KERNEL_OUT:-$PROJECT_DIR/kernel/build}"
GUEST="${GUEST_DIR:-$PROJECT_DIR/guest}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
ARCH=arm64
JOBS="${JOBS:-2}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
need make
need "${CROSS_COMPILE}gcc"
[ -d "$SRC" ] || { echo "missing kernel source: $SRC" >&2; exit 1; }
[ -x "$SRC/scripts/config" ] || { echo "missing scripts/config in $SRC" >&2; exit 1; }

mkdir -p "$OUT_ROOT" "$GUEST" "$PROJECT_DIR/docs"

# These are deliberately built-in: the image's current 6.18.44 modules remain
# usable as a fallback, while each custom kernel can boot without a module tree.
COMMON_Y=(
  CONFIG_PRINTK CONFIG_PRINTK_TIME CONFIG_BUG CONFIG_ELF_CORE CONFIG_BINFMT_ELF CONFIG_BINFMT_SCRIPT CONFIG_MULTIUSER
  CONFIG_BLK_DEV_INITRD CONFIG_DEVTMPFS CONFIG_DEVTMPFS_MOUNT CONFIG_DEVTMPFS_SAFE
  CONFIG_UEVENT_HELPER CONFIG_UEVENT_HELPER_PATH="/sbin/hotplug"
  CONFIG_PROC_FS CONFIG_SYSFS CONFIG_TMPFS CONFIG_DEVPTS_FS
  CONFIG_NAMESPACES CONFIG_UTS_NS CONFIG_IPC_NS CONFIG_PID_NS CONFIG_NET_NS CONFIG_FHANDLE
  CONFIG_BLOCK CONFIG_BLK_DEV CONFIG_EXT4_FS CONFIG_JBD2 CONFIG_FS_MBCACHE
  CONFIG_NET CONFIG_INET CONFIG_PACKET CONFIG_UNIX
  CONFIG_SYSVIPC CONFIG_POSIX_TIMERS CONFIG_FUTEX CONFIG_EPOLL CONFIG_SIGNALFD
  CONFIG_TIMERFD CONFIG_EVENTFD CONFIG_AIO
  CONFIG_NET_CORE CONFIG_NETDEVICES CONFIG_ETHERNET
  CONFIG_PCI CONFIG_PCI_HOST_GENERIC CONFIG_VIRTIO_MENU CONFIG_VIRTIO CONFIG_VIRTIO_PCI
  CONFIG_VIRTIO_BLK CONFIG_VIRTIO_NET CONFIG_VIRTIO_MMIO
  CONFIG_RNG_CORE CONFIG_VIRTIO_RNG
  CONFIG_USB_SUPPORT CONFIG_USB CONFIG_USB_COMMON CONFIG_USB_XHCI_HCD
  CONFIG_USB_XHCI_PCI CONFIG_USB_XHCI_PLATFORM CONFIG_USB_HUB
  CONFIG_FW_LOADER CONFIG_FW_LOADER_COMPRESS CONFIG_FW_LOADER_COMPRESS_ZSTD
  CONFIG_WLAN CONFIG_WLAN_VENDOR_ATH CONFIG_ATH_COMMON CONFIG_ATH9K_HW
  CONFIG_ATH9K_COMMON CONFIG_ATH9K_HTC CONFIG_CFG80211 CONFIG_MAC80211
  CONFIG_CRYPTO CONFIG_CRYPTO_AES CONFIG_CRYPTO_CMAC
  CONFIG_TTY CONFIG_SERIAL_CORE CONFIG_SERIAL_AMBA_PL011
  CONFIG_SERIAL_AMBA_PL011_CONSOLE
  CONFIG_NO_HZ CONFIG_NO_HZ_IDLE CONFIG_PREEMPT_NONE CONFIG_HZ_100
  CONFIG_SMP CONFIG_NR_CPUS=8
)

TIER_B_Y=(
  CONFIG_USB_ACM CONFIG_USB_SERIAL CONFIG_USB_SERIAL_GENERIC
  CONFIG_USB_SERIAL_FTDI_SIO CONFIG_USB_SERIAL_CP210X CONFIG_USB_SERIAL_PL2303
  CONFIG_USB_SERIAL_CH341
)

REQUIRED_Y=(
  CONFIG_CFG80211 CONFIG_MAC80211 CONFIG_ATH_COMMON CONFIG_ATH9K_HW
  CONFIG_ATH9K_COMMON CONFIG_ATH9K_HTC CONFIG_USB_XHCI_HCD
  CONFIG_VIRTIO_BLK CONFIG_EXT4_FS CONFIG_PACKET CONFIG_FW_LOADER
  CONFIG_FW_LOADER_COMPRESS_ZSTD
)

set_config_y() {
  local out="$1"; shift
  local sym
  for sym in "$@"; do
    if [[ "$sym" == *=* ]]; then
      "$SRC/scripts/config" --file "$out/.config" --set-val "${sym%%=*}" "${sym#*=}"
    else
      "$SRC/scripts/config" --file "$out/.config" --enable "$sym"
    fi
  done
}

set_config_n() {
  local out="$1"; shift
  local sym
  for sym in "$@"; do
    "$SRC/scripts/config" --file "$out/.config" --disable "$sym"
  done
}

build_tier() {
  local tier="$1"; shift
  local out="$OUT_ROOT/build-$tier"
  local localversion="-$tier"
  echo "[kernel:$tier] configuring tinyconfig"
  rm -rf "$out"
  mkdir -p "$out"
  make -C "$SRC" O="$out" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" tinyconfig >/dev/null
  "$SRC/scripts/config" --file "$out/.config" --set-str CONFIG_LOCALVERSION "$localversion"
  "$SRC/scripts/config" --file "$out/.config" --disable CONFIG_LOCALVERSION_AUTO
  set_config_y "$out" "${COMMON_Y[@]}" "$@"
  # Explicitly avoid options that are irrelevant to this headless guest.
  set_config_n "$out" CONFIG_MODULES CONFIG_KALLSYMS CONFIG_DEBUG_INFO CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT CONFIG_AUDIT CONFIG_KPROBES CONFIG_TRACING CONFIG_FTRACE CONFIG_BPF_SYSCALL CONFIG_NETFILTER
  make -C "$SRC" O="$out" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig >/dev/null
  echo "[kernel:$tier] verifying required symbols before compile"
  local sym val
  for sym in "${REQUIRED_Y[@]}"; do
    val="$(sed -n "s/^${sym}=//p" "$out/.config" | head -n1)"
    if [ "$val" != y ]; then
      echo "required symbol is not built-in: $sym=${val:-missing}" >&2
      exit 1
    fi
  done
  echo "[kernel:$tier] compiling with JOBS=$JOBS"
  make -C "$SRC" O="$out" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" Image >/dev/null
  local image="$out/arch/arm64/boot/Image"
  [ -s "$image" ] || { echo "kernel Image missing for $tier" >&2; exit 1; }
  cp -f "$image" "$GUEST/vmlinuz-$tier"
  cp -f "$out/.config" "$PROJECT_DIR/docs/kernel-$tier.config"
  make -C "$SRC" O="$out" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" savedefconfig >/dev/null
  cp -f "$out/defconfig" "$PROJECT_DIR/docs/kernel-$tier.defconfig"
  "$SRC/scripts/config" --file "$out/.config" --enable CONFIG_IKCONFIG
  "$SRC/scripts/config" --file "$out/.config" --enable CONFIG_IKCONFIG_PROC
  printf '%s\n' "[kernel:$tier] release=$(make -s -C "$SRC" O="$out" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" kernelrelease)" \
    "image=$(stat -c '%s' "$image") bytes" \
    "config=$(wc -l < "$out/.config") lines" | tee "$PROJECT_DIR/docs/kernel-$tier.build-info"
}

if [ "${ONLY_TIER:-}" != safe ]; then
  build_tier tiny
fi
if [ "${ONLY_TIER:-}" != tiny ]; then
  build_tier safe "${TIER_B_Y[@]}"
fi

  cat > "$GUEST/KERNEL-TIERS.md" <<'EOF'
# Custom kernel tiers

- `vmlinuz-tiny`: Tier A ultra-minimal, built-in Wi-Fi/USB/virtio/ext4/serial essentials.
- `vmlinuz-safe`: Tier B safe-minimal, Tier A plus USB hub and common CDC/USB-serial drivers.
- `vmlinuz-lts`: original Alpine linux-lts fallback, unchanged.

The custom kernels are intentionally shipped beside the Alpine kernel. The launcher selects them only when `KERNEL_TIER=tiny` or `KERNEL_TIER=safe` is requested.
EOF

echo "kernel tiers built successfully"
ls -lh "$GUEST/vmlinuz-tiny" "$GUEST/vmlinuz-safe" "$GUEST/vmlinuz-lts" 2>/dev/null || true
