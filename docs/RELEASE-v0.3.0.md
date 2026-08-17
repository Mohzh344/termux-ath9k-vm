# v0.3.0 — Unified launcher, reliable local console, and safer release workflow

## Fixed

- Fixed the unified launcher exiting immediately on a first run: optional/missing or stale `.vm-launcher.conf` values now return success under `set -e`.
- Fixed the direct USB wrapper path and separated USB permission inheritance from interactive serial console handling.
- Fixed serial-console authentication failures caused by the shipped BusyBox shadow fallback path.
- Replaced the unreliable local serial login with a direct root shell on `ttyAMA0`; the release image intentionally has no username/password prompt on its local QEMU serial console.
- Added monitor socket collision protection so a manual launcher cannot silently replace another VM's monitor socket.
- Changed pinned Alpine artifact downloads from HTTP to HTTPS-only curl transport.
- Corrected the Termux boot-test interpreter and made its timeout configurable for slow rootless TCG boots.

## Added

- `bin/vm-launcher.sh`: recommended interactive entry point with persistent RAM/SMP/image choices, USB detection, Android permission flow, socket console for USB mode, status messages, and cleanup.
- `bin/console-connect.sh`: advanced/manual connection to a Unix-socket serial console.
- `bin/launch-vm-rescue.sh`: low-level recovery boot path.
- `src/repair-root-login.sh`: offline repair helper for a stopped image using the older login path.
- `src/enable-root-autologin.sh`: offline recovery helper that configures the direct root serial shell.
- `src/package-release.sh`: sparse-aware archive builder which refuses a running image and regenerates the in-archive guest checksum manifest.
- Offline `securetty` verification/repair in the unified launcher.

## Performance defaults

The recommended rootless QEMU profile is now **768 MiB RAM and 1 vCPU**. The launcher explicitly selects TCG and uses single-thread TCG for one vCPU; it selects multi-thread TCG only when higher SMP is requested.

## Security boundary

The direct root shell is intentionally for the private QEMU serial console on the phone. Do not expose its Unix socket, terminal, or a future remote-login service to untrusted users. Configure authentication before enabling any remote access.

## Verification performed

- All shipped Bash scripts passed syntax validation.
- QEMU accepted the selected TCG options in a local smoke test.
- The corrected guest image was checked with `e2fsck -fn` after its controlled repair.
- An actual 768 MiB / 1-vCPU QEMU boot reached a `~ #` root shell with no login prompt.
- The release archive and its SHA-256 checksum are verified during packaging.
- AR9271/OTG Android USB attachment remains hardware-dependent and must be tested on the target adapter and phone.
