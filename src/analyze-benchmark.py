#!/usr/bin/env python3
from pathlib import Path
import csv
import statistics

project = Path(__file__).resolve().parents[1]
csv_path = project / 'benchmarks' / 'matrix' / 'results.csv'
out_path = project / 'benchmarks' / 'matrix' / 'SUMMARY.md'
rows = list(csv.DictReader(csv_path.open()))

def num(row, key):
    try:
        return float(row[key])
    except (ValueError, TypeError):
        return None

def avg(items):
    vals = [v for v in items if v is not None]
    return statistics.mean(vals) if vals else None

lines = [
    '# v0.3.0 TCG Benchmark Matrix',
    '',
    'All runs used the same Alpine disk and direct-root custom-kernel boot path. Each configuration was run once on the sandbox host; results are comparative rather than a promise of identical Android performance.',
    '',
    '| Tier | CPU | TCG thread | SMP | RAM MB | Host wall s | Guest root s | Idle available MB | Workload | Status |',
    '|---|---|---:|---:|---:|---:|---:|---:|---:|---|',
]
for r in rows:
    lines.append('| {tier} | {cpu} | {thread} | {smp} | {ram} | {wall} | {root} | {mem} | {work} | {status} |'.format(
        tier=r['tier'], cpu=r['cpu'], thread=r['tcg_thread'], smp=r['smp'], ram=r['ram_mb'],
        wall=r['host_wall_s'], root=r['guest_root_s'], mem=r['idle_mem_available_mb'],
        work=r['cpu_workload_s'], status=r['status']))

lines += ['', '## Aggregate observations', '', '| Group | Runs | Mean host wall s | Mean guest root s | Mean idle available MB |', '|---|---:|---:|---:|---:|']
groups = {}
for r in rows:
    key = (r['tier'], r['cpu'], r['tcg_thread'], r['smp'], r['ram_mb'])
    groups.setdefault(key, []).append(r)
for key, group in sorted(groups.items()):
    wall = avg(num(r, 'host_wall_s') for r in group)
    root = avg(num(r, 'guest_root_s') for r in group)
    mem = avg(num(r, 'idle_mem_available_mb') for r in group)
    lines.append('| {}/{}/{}/smp{} / {} MB | {} | {:.3f} | {} | {} |'.format(
        key[0], key[1], key[2], key[3], key[4], len(group), wall,
        f'{root:.3f}' if root is not None else 'NA',
        f'{mem:.1f}' if mem is not None else 'NA'))

best = min(rows, key=lambda r: num(r, 'host_wall_s') or 1e99)
lines += ['', '## Fastest recorded configuration', '',
          f"The fastest recorded run was **{best['tier']} / {best['cpu']} / TCG {best['tcg_thread']} / SMP {best['smp']} / {best['ram_mb']} MB**, with host wall time **{best['host_wall_s']} s** and idle available memory **{best['idle_mem_available_mb']} MB**.", '',
          'These numbers include the benchmark probe delay and the time needed to shut down the guest. Use `guest_root_s` as the kernel/root-mount timing where printk timestamps are available. Android results will vary with device thermals, QEMU build, and USB activity.']
out_path.write_text('\n'.join(lines) + '\n')
print(out_path)
print(f'runs={len(rows)}')
print(f"fastest={best['tier']}/{best['cpu']}/{best['tcg_thread']}/smp{best['smp']}/{best['ram_mb']}MB host_wall={best['host_wall_s']}s")
