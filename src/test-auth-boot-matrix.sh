#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FULL_SOURCE="${FULL_SOURCE:-$(find /tmp /home/ubuntu -type f -path '*/guest/alpine-ath9k.img' -print -quit 2>/dev/null || true)}"
LITE_SOURCE="${LITE_SOURCE:-$BASE_DIR/guest/alpine-ath9k-v030-lite.img}"
FULL_KERNEL_SOURCE="${FULL_KERNEL_SOURCE:-$(dirname "$FULL_SOURCE")/vmlinuz-lts}"
FULL_INITRD_SOURCE="${FULL_INITRD_SOURCE:-$(dirname "$FULL_SOURCE")/initramfs-lts}"
[ -f "$FULL_SOURCE" ] || { echo "missing Full source image: $FULL_SOURCE" >&2; exit 1; }
[ -f "$LITE_SOURCE" ] || { echo "missing Lite source image: $LITE_SOURCE" >&2; exit 1; }
[ -f "$FULL_KERNEL_SOURCE" ] || { echo "missing Full kernel: $FULL_KERNEL_SOURCE" >&2; exit 1; }
[ -f "$FULL_INITRD_SOURCE" ] || { echo "missing Full initramfs: $FULL_INITRD_SOURCE" >&2; exit 1; }

T="$(mktemp -d /tmp/auth-boot-matrix.XXXXXX)"
trap 'rc=$?; echo "MATRIX_TEMP=$T" >&2; if [ "$rc" -eq 0 ]; then rm -rf "$T"; fi; exit "$rc"' EXIT
source "$BASE_DIR/src/vm-storage-lib.sh"

copy_full_bundle() {
  local d="$1"
  mkdir -p "$d/guest"
  cp --sparse=always --reflink=auto "$FULL_SOURCE" "$d/guest/alpine-ath9k.img"
  cp -p "$FULL_KERNEL_SOURCE" "$d/guest/vmlinuz-lts"
  cp -p "$FULL_INITRD_SOURCE" "$d/guest/initramfs-lts"
}
copy_lite_bundle() {
  local d="$1"
  mkdir -p "$d/guest"
  cp --sparse=always --reflink=auto "$LITE_SOURCE" "$d/guest/alpine-ath9k-v030-lite.img"
  cp -p "$BASE_DIR/guest/vmlinuz-tiny" "$d/guest/vmlinuz-tiny"
  cp -p "$BASE_DIR/guest/vmlinuz-safe" "$d/guest/vmlinuz-safe"
  cp -p "$BASE_DIR/guest/vmlinuz-lts-lite" "$d/guest/vmlinuz-lts-lite"
  cp -p "$BASE_DIR/guest/initramfs-lts-lite" "$d/guest/initramfs-lts-lite"
}

set_known_password() {
  local image="$1" password_file="$T/password"
  openssl passwd -6 -salt v035 'testpass123' > "$T/hash"
  debugfs -R "dump /etc/shadow $password_file" "$image" >/dev/null
  awk -F: -v OFS=: -v h="$(cat "$T/hash")" '$1=="root"{$2=h} {print}' "$password_file" > "$T/shadow"
  vm_guest_write_file "$image" "$T/shadow" /etc/shadow 0100600
}

run_qemu() {
  local variant="$1" image="$2" kernel="$3" initrd="$4" log="$5"
  local -a args=(
    -machine virt -accel tcg,thread=single -cpu max -m 768M -smp 1
    -kernel "$kernel"
    -append 'console=ttyAMA0,115200 root=/dev/vda rw rootflags=rw rootfstype=ext4 rootwait'
    -drive "if=none,id=rootdisk,format=raw,file=$image,cache=writeback"
    -device virtio-blk-pci,drive=rootdisk -device virtio-rng-pci -device qemu-xhci,id=xhci
    -snapshot -display none -monitor none -serial "file:$log"
  )
  [ -n "$initrd" ] && args+=( -initrd "$initrd" )
  timeout 180s qemu-system-aarch64 "${args[@]}" >"$log.qemu" 2>&1
  rc=$?
  [ -f "$log.qemu" ] && cat "$log.qemu" >> "$log"
  rm -f "$log.qemu"
  return "$rc"
}

run_case() {
  local variant="$1" mode="$2" case_dir state bundle log image kernel initrd
  case_dir="$T/$variant-$mode"
  state="$case_dir/state"
  bundle="$case_dir/bundle"
  log="$case_dir/boot.log"
  mkdir -p "$state"
  VM_STATE_ROOT="$state"
  export VM_STATE_ROOT
  if [ "$variant" = full ]; then
    copy_full_bundle "$bundle/full"
    image="$state/full/alpine-ath9k.img"
    kernel="$bundle/full/guest/vmlinuz-lts"
    initrd="$bundle/full/guest/initramfs-lts"
    vm_storage_init "$case_dir" "$bundle/full" "$bundle/lite" >/dev/null
  else
    copy_lite_bundle "$bundle/lite"
    image="$state/lite/alpine-ath9k-v030-lite.img"
    kernel="$bundle/lite/guest/vmlinuz-safe"
    initrd=""
    vm_storage_init "$case_dir" "$bundle/full" "$bundle/lite" >/dev/null
  fi
  [ -f "$image" ] || { echo "FAIL: image was not adopted for $variant/$mode" >&2; exit 1; }
  if [ "$mode" = login ]; then set_known_password "$image"; fi
  CREATE_BACKUP=0 "$BASE_DIR/src/configure-console-auth.sh" "$image" "$mode" >/dev/null
  AUTH_MODE_FOR_CASE="$mode"
  set +e
  run_qemu "$variant" "$image" "$kernel" "$initrd" "$log"
  rc=$?
  set -e
  if ! grep -Eq 'Alpine Init|OpenRC .*starting|login:|~#|\(none\):~#' "$log"; then
    echo "FAIL: $variant/$mode did not reach a recognizable console (qemu_rc=$rc)" >&2
    tail -100 "$log" >&2
    exit 1
  fi
  if [ "$mode" = login ] && grep -Eq 'Login incorrect|login incorrect' "$log"; then
    echo "FAIL: $variant/$mode rejected the known password" >&2
    tail -80 "$log" >&2
    exit 1
  fi
  vm_validate_image "$image"
  echo "PASS: $variant/$mode console reached and image remained structurally valid (qemu_rc=$rc)"
}

for variant in full lite; do
  for mode in root-console login login-empty; do
    run_case "$variant" "$mode"
  done
done

echo 'All Full/Lite authentication boot-matrix cases passed.'
