#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FULL_SOURCE="${FULL_SOURCE:-$(find /tmp /home/ubuntu -type f -path '*/guest/alpine-ath9k.img' -print -quit 2>/dev/null || true)}"
LITE_SOURCE="${LITE_SOURCE:-$BASE_DIR/guest/alpine-ath9k-v030-lite.img}"
FULL_KERNEL_SOURCE="${FULL_KERNEL_SOURCE:-$(dirname "$FULL_SOURCE")/vmlinuz-lts}"
FULL_INITRD_SOURCE="${FULL_INITRD_SOURCE:-$(dirname "$FULL_SOURCE")/initramfs-lts}"
[ -f "$FULL_SOURCE" ] && [ -f "$LITE_SOURCE" ] || { echo 'Full/Lite source images are required.' >&2; exit 1; }
[ -f "$FULL_KERNEL_SOURCE" ] && [ -f "$FULL_INITRD_SOURCE" ] || { echo 'Full kernel/initramfs are required.' >&2; exit 1; }

T="$(mktemp -d /tmp/login-session-test.XXXXXX)"
trap 'rc=$?; if [ -n "${QEMU_PID:-}" ]; then kill "$QEMU_PID" 2>/dev/null || true; wait "$QEMU_PID" 2>/dev/null || true; fi; echo "LOGIN_TEMP=$T" >&2; if [ "$rc" -eq 0 ]; then rm -rf "$T"; fi; exit "$rc"' EXIT
source "$BASE_DIR/src/vm-storage-lib.sh"

make_full() {
  local d="$1"
  mkdir -p "$d/guest"
  cp --sparse=always --reflink=auto "$FULL_SOURCE" "$d/guest/alpine-ath9k.img"
  cp -p "$FULL_KERNEL_SOURCE" "$d/guest/vmlinuz-lts"
  cp -p "$FULL_INITRD_SOURCE" "$d/guest/initramfs-lts"
}
make_lite() {
  local d="$1"
  mkdir -p "$d/guest"
  cp --sparse=always --reflink=auto "$LITE_SOURCE" "$d/guest/alpine-ath9k-v030-lite.img"
  cp -p "$BASE_DIR/guest/vmlinuz-safe" "$d/guest/vmlinuz-safe"
  cp -p "$BASE_DIR/guest/vmlinuz-tiny" "$d/guest/vmlinuz-tiny"
  cp -p "$BASE_DIR/guest/vmlinuz-lts-lite" "$d/guest/vmlinuz-lts-lite"
  cp -p "$BASE_DIR/guest/initramfs-lts-lite" "$d/guest/initramfs-lts-lite"
}
set_password() {
  local image="$1"
  openssl passwd -6 -salt v035 'testpass123' > "$T/hash"
  debugfs -R "dump /etc/shadow $T/shadow.old" "$image" >/dev/null
  awk -F: -v OFS=: -v h="$(cat "$T/hash")" '$1=="root"{$2=h} {print}' "$T/shadow.old" > "$T/shadow.new"
  vm_guest_write_file "$image" "$T/shadow.new" /etc/shadow 0100600
}

run_login_case() {
  local variant="$1" mode="$2" case_dir="$T/$variant-$mode" state bundle image kernel initrd socket log
  case_dir="$T/$variant-$mode"
  state="$case_dir/state"
  bundle="$case_dir/bundle"
  socket="$case_dir/serial.sock"
  log="$case_dir/session.log"
  mkdir -p "$state"
  if [ "$variant" = full ]; then
    make_full "$bundle/full"
    VM_STATE_ROOT="$state" vm_storage_init "$case_dir" "$bundle/full" "$bundle/lite" >/dev/null
    image="$state/full/alpine-ath9k.img"
    kernel="$bundle/full/guest/vmlinuz-lts"
    initrd="$bundle/full/guest/initramfs-lts"
  else
    make_lite "$bundle/lite"
    VM_STATE_ROOT="$state" vm_storage_init "$case_dir" "$bundle/full" "$bundle/lite" >/dev/null
    image="$state/lite/alpine-ath9k-v030-lite.img"
    kernel="$bundle/lite/guest/vmlinuz-safe"
    initrd=""
  fi
  if [ "$mode" = login ]; then set_password "$image"; fi
  CREATE_BACKUP=0 "$BASE_DIR/src/configure-console-auth.sh" "$image" "$mode" >/dev/null
  mkdir -p "$case_dir"
  local -a args=(
    -machine virt -accel tcg,thread=single -cpu max -m 768M -smp 1
    -kernel "$kernel"
    -append 'console=ttyAMA0,115200 root=/dev/vda rw rootflags=rw rootfstype=ext4 rootwait'
    -drive "if=none,id=rootdisk,format=raw,file=$image,cache=writeback"
    -device virtio-blk-pci,drive=rootdisk -device virtio-rng-pci -device qemu-xhci,id=xhci
    -snapshot -display none -monitor none
    -chardev "socket,id=serial0,path=$socket,server=on,wait=off" -serial chardev:serial0
  )
  [ -n "$initrd" ] && args+=( -initrd "$initrd" )
  qemu-system-aarch64 "${args[@]}" >"$case_dir/qemu.log" 2>&1 & QEMU_PID=$!
  for _ in $(seq 1 120); do
    [ -S "$socket" ] && break
    kill -0 "$QEMU_PID" 2>/dev/null || { cat "$case_dir/qemu.log" >&2; exit 1; }
    sleep 0.5
  done
  [ -S "$socket" ] || { echo "serial socket timeout: $variant/$mode" >&2; exit 1; }
  timeout 140s python3 "$BASE_DIR/src/serial-login-client.py" "$socket" "$log" "$mode" || true
  if ! grep -Eq 'login:|~#|\(none\):~#' "$log"; then
    echo "FAIL: $variant/$mode did not reach login/session prompt" >&2
    tail -100 "$log" >&2
    exit 1
  fi
  if grep -Eqi 'login incorrect|authentication failure' "$log"; then
    echo "FAIL: $variant/$mode rejected the session credentials" >&2
    tail -100 "$log" >&2
    exit 1
  fi
  kill "$QEMU_PID" 2>/dev/null || true
  wait "$QEMU_PID" 2>/dev/null || true
  QEMU_PID=""
  vm_validate_image "$image"
  echo "PASS: $variant/$mode accepted the session input and image remained valid"
}

for variant in full lite; do
  for mode in login login-empty; do
    run_login_case "$variant" "$mode"
  done
done

echo 'All real login-session cases passed.'
