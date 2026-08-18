# v0.3.0 Benchmark Report

## Test environment

The benchmark was run on the project sandbox with QEMU 8.2.2, ARM64 Alpine 3.24.1, Linux 6.18.44, and TCG without KVM. The custom tiers used direct-root boot without the Alpine initramfs; the `linux-lts` fallback used the original 8.9 MB initramfs. Every matrix configuration was run once, so the values are comparative measurements rather than Android performance guarantees.

## Matrix result

The full matrix contains **48/48 passing runs**. It covers both custom tiers, `max`, `cortex-a72`, and `cortex-a76`, TCG `multi` and `single`, and SMP 1, 2, 4, and 6. RAM was paired with SMP as 512 MB, 768 MB, 1024 MB, and 1536 MB respectively.

| Metric | Result |
|---|---:|
| Matrix runs | 48 |
| Passing runs | 48 |
| Failing runs | 0 |
| Fastest recorded host wall time | 26.006 s |
| Fastest recorded configuration | Tier B / `max` / TCG multi / SMP 4 / 1024 MB |
| Recommended low-resource configuration | Tier B / `max` / TCG multi / SMP 1 / 512 MB |
| Idle available RAM at 512 MB profile | approximately 480 MB |
| Tier A kernel image | approximately 6.9 MB |
| Tier B kernel image | approximately 7.0 MB |
| Alpine linux-lts kernel image | approximately 13 MB |
| Alpine linux-lts initramfs | approximately 8.9 MB |
| Lite allocated disk usage | approximately 305 MB |
| Full allocated disk usage | approximately 317 MB |

The full raw matrix and per-run serial logs are in [`benchmarks/matrix/results.csv`](../benchmarks/matrix/results.csv) and [`benchmarks/matrix/`](../benchmarks/matrix/). The generated readable summary is [`benchmarks/matrix/SUMMARY.md`](../benchmarks/matrix/SUMMARY.md).

## Fallback baseline

A separate `linux-lts` run using 768 MB and SMP 2 reached Alpine Init at approximately 6.5 guest seconds, mounted root at approximately 23.1 guest seconds, and reached a working root serial login. Its host wall time was 79.232 seconds because the probe intentionally waited longer for the slower initramfs path. This is not directly comparable to the 22-second custom-tier probe delay, but it confirms that `linux-lts` remains a working fallback.

## Interpretation

The strongest size and boot-path improvement is not an aggressive removal of Wi-Fi capabilities. It is the combination of built-in device essentials and direct-root boot. This keeps `cfg80211`, `mac80211`, `ath9k_htc`, AR9271 firmware loading, XHCI, virtio block, ext4, packet sockets, and the serial console available while avoiding the module/switch-root handoff that stalled the first custom-kernel attempt.

The results do not prove that SMP 4 or 6 is faster on an Android phone. TCG scheduling, thermal throttling, and the number of host cores can reverse the result. The `wifi-only` profile therefore remains conservative at 512 MB and one vCPU; users can use the matrix runner on their own device and select a profile based on observed stability.

## Reproduction

Run one measurement:

```sh
RUNS=1 KERNEL_TIER=safe PROFILE=wifi-only RAM=512 SMP=1 \
  CPU_MODEL=max TCG_THREAD=multi ./src/benchmark.sh
```

Run the complete matrix:

```sh
TIERS='safe tiny' CPUS='max cortex-a72 cortex-a76' \
  TCG_THREADS='multi single' SMPS='1 2 4 6' \
  ./src/run-benchmark-matrix.sh
```
