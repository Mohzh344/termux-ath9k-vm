#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QEMU="${QEMU:-qemu-system-aarch64}"
DISK="${DISK:-$PROJECT_DIR/guest/alpine-ath9k-v030-lite.img}"
KERNEL_TIER="${KERNEL_TIER:-safe}"
RAM="${RAM:-512}"
SMP="${SMP:-1}"
CPU_MODEL="${CPU_MODEL:-max}"
TCG_THREAD="${TCG_THREAD:-multi}"
PROFILE="${PROFILE:-wifi-only}"
RUNS="${RUNS:-1}"
OUT_DIR="${OUT_DIR:-$PROJECT_DIR/benchmarks/runs}"
WORKLOAD_MB="${WORKLOAD_MB:-128}"
TIMEOUT="${TIMEOUT:-90}"
PROBE_DELAY="${PROBE_DELAY:-28}"

case "$KERNEL_TIER" in
  tiny|safe) KERNEL="$PROJECT_DIR/guest/vmlinuz-$KERNEL_TIER"; INITRD="" ;;
  lts|full) KERNEL="$PROJECT_DIR/guest/vmlinuz-lts"; INITRD="$PROJECT_DIR/guest/initramfs-lts" ;;
  *) echo 'KERNEL_TIER must be tiny, safe, or lts' >&2; exit 2 ;;
esac
[ -f "$DISK" ] || { echo "missing disk: $DISK" >&2; exit 1; }
[ -f "$KERNEL" ] || { echo "missing kernel: $KERNEL" >&2; exit 1; }
[ -z "$INITRD" ] || [ -f "$INITRD" ] || { echo "missing initrd: $INITRD" >&2; exit 1; }
command -v "$QEMU" >/dev/null || { echo "missing $QEMU" >&2; exit 1; }
mkdir -p "$OUT_DIR"

csv="$OUT_DIR/results.csv"
if [ ! -s "$csv" ]; then
  printf '%s\n' 'timestamp,profile,tier,ram_mb,smp,cpu,tcg_thread,run,host_wall_s,guest_root_s,guest_login_marker,idle_mem_available_mb,cpu_workload_s,status,log' > "$csv"
fi

for run in $(seq 1 "$RUNS"); do
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  log="$OUT_DIR/${stamp}-${KERNEL_TIER}-${CPU_MODEL}-smp${SMP}-tcg${TCG_THREAD}-run${run}.log"
  start_ns="$(date +%s%N)"
  qemu_args=(
    -machine virt
    -cpu "$CPU_MODEL"
    -accel "tcg,thread=$TCG_THREAD"
    -m "${RAM}M"
    -smp "$SMP"
    -kernel "$KERNEL"
    -append 'console=ttyAMA0,115200 root=/dev/vda rw rootflags=rw rootfstype=ext4 rootwait'
    -drive "if=none,id=rootdisk,format=raw,file=$DISK,cache=writeback"
    -device virtio-blk-pci,drive=rootdisk
    -device virtio-rng-pci
    -device qemu-xhci,id=xhci
    -nographic -monitor none -serial stdio
  )
  if [ -n "$INITRD" ]; then qemu_args+=( -initrd "$INITRD" ); fi
  set +e
  {
    sleep "$PROBE_DELAY"
    printf '%s\n' \
      'echo __BENCH_PROBE__' \
      'awk '\''/^MemAvailable:/{print "BENCH_IDLE_MEM_MB=" int($2/1024)}'\'' /proc/meminfo' \
      "echo BENCH_WORKLOAD_START" \
      "time dd if=/dev/zero of=/dev/null bs=1M count=$WORKLOAD_MB" \
      'echo BENCH_WORKLOAD_END' \
      'echo BENCH_PROBE_DONE' \
      'poweroff -f'
    sleep 4
  } | timeout "$TIMEOUT" "$QEMU" "${qemu_args[@]}" >"$log" 2>&1
  qemu_rc=$?
  set -e
  end_ns="$(date +%s%N)"

  host_wall_s="$(awk -v d="$((end_ns-start_ns))" 'BEGIN {printf "%.3f", d/1000000000}')"
  guest_root_s="$(grep -m1 -E 'VFS: Mounted root|Mounting root: ok' "$log" | sed -n 's/.*\[[[:space:]]*\([0-9.]*\)\].*/\1/p' || true)"
  guest_login_marker=0
  grep -q 'root login on' "$log" && guest_login_marker=1 || true
  idle_mem="$(sed -n 's/.*BENCH_IDLE_MEM_MB=\([0-9][0-9]*\).*/\1/p' "$log" | head -n1)"
  workload="$(awk '/real[[:space:]]/{print $2; exit}' "$log" || true)"
  status=FAIL
  if grep -q 'root login on' "$log" && grep -q 'BENCH_PROBE_DONE' "$log"; then status=PASS; fi
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$stamp" "$PROFILE" "$KERNEL_TIER" "$RAM" "$SMP" "$CPU_MODEL" "$TCG_THREAD" "$run" "$host_wall_s" \
    "${guest_root_s:-NA}" "$guest_login_marker" "${idle_mem:-NA}" "${workload:-NA}" "$status" "$log" >> "$csv"
  echo "[$status] tier=$KERNEL_TIER profile=$PROFILE ram=${RAM}M smp=$SMP cpu=$CPU_MODEL tcg=$TCG_THREAD log=$log"
done

printf '%s\n' "results=$csv"
