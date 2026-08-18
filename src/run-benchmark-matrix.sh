#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$PROJECT_DIR/benchmarks/matrix}"
mkdir -p "$OUT_DIR"

run_one() {
  local tier="$1" cpu="$2" thread="$3" smp="$4" ram="$5"
  echo "[matrix] tier=$tier cpu=$cpu thread=$thread smp=$smp ram=$ram"
  OUT_DIR="$OUT_DIR" RUNS=1 KERNEL_TIER="$tier" PROFILE=matrix \
    RAM="$ram" SMP="$smp" CPU_MODEL="$cpu" TCG_THREAD="$thread" \
    PROBE_DELAY="${PROBE_DELAY:-25}" TIMEOUT="${TIMEOUT:-75}" WORKLOAD_MB="${WORKLOAD_MB:-64}" \
    "$PROJECT_DIR/src/benchmark.sh"
}


for tier in ${TIERS:-safe tiny}; do
  for cpu in ${CPUS:-max cortex-a72 cortex-a76}; do
    for thread in ${TCG_THREADS:-multi single}; do
      for smp in ${SMPS:-1 2 4 6}; do
        case "$smp" in 1) ram=512 ;; 2) ram=768 ;; 4) ram=1024 ;; 6) ram=1536 ;; esac
        run_one "$tier" "$cpu" "$thread" "$smp" "$ram"
      done
    done
  done
done

printf '%s\n' "matrix_results=$OUT_DIR/results.csv"
