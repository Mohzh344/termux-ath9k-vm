# v0.3.0-lite

`v0.3.0-lite` is an additive companion to the existing `v0.3.0` Full release. The Full image, its build scripts, unified launcher, USB wrappers, recovery helpers, and published release are treated as the canonical user implementation and are not replaced by this Lite work.

## What Lite contains

| Component | Lite behavior |
|---|---|
| Guest | Alpine Linux ARM64 with the same 6.18.44 Alpine base and AR9271 firmware inputs |
| Kernel options | `vmlinuz-tiny` Tier A and `vmlinuz-safe` Tier B, both direct-root and TCG-oriented |
| Fallback | `vmlinuz-lts-lite` plus `initramfs-lts-lite` |
| Console | The same private local serial root shell behavior as Full; no password is required or published |
| Wi-Fi runtime | `iw`, `lsusb`, `kmod`, `ethtool`, `wireless-tools`, `wifi-diagnose` |
| Optional tools | `/usr/bin/install-wifi-tools` installs the base Wi-Fi packages later; it does not start capture or attack actions |
| Excluded by default | `aircrack-ng`, `tcpdump`, `hostapd`, hcxdumptool/hcxtools, WPS tools, OpenSSH, Python, and compiler toolchains |

The Lite image is intentionally a **runtime image**, not a replacement for the Full security-tool image. Its purpose is to minimize the first boot and stored package footprint on Android/Termux. The optional installer requires network access and additional guest storage when run.

## Recommended launch

From the extracted Lite archive:

```sh
chmod 700 bin/*.sh src/*.sh
PROFILE=wifi-only KERNEL_TIER=safe ./bin/launch-vm-lite.sh
```

The profiles are conservative for QEMU TCG without KVM:

| Profile | RAM | vCPU | Intended use |
|---|---:|---:|---|
| `wifi-only` | 512 MiB | 1 | AR9271-only diagnostics and a private console |
| `balanced` | 768 MiB | 2 | Interactive package installation and light tooling |
| `default` | 1024 MiB | 2 | General fallback |
| `legacy` | 1536 MiB | 4 | Compatibility fallback only |

The custom tiers boot without an initramfs so the Alpine switch-root path is not needed. Select `KERNEL_TIER=lts` to use the Lite lts kernel/initramfs fallback.

## USB direct mode

The existing Full USB scripts are left untouched. Lite has a separate additive wrapper:

```sh
./bin/usb-attach-lite-direct.sh /dev/bus/usb/001/003
```

The wrapper uses the same Termux USB permission model and the same AR9271 USB ID (`0cf3:9271`) as the Full path. Test direct mode first; usb-redir remains available through the Full compatibility path if needed.

## Install tools after boot

The installer is present as both `/usr/local/sbin/install-wifi-tools` and `/usr/bin/install-wifi-tools`:

```sh
install-wifi-tools
```

It installs the lightweight Alpine runtime set (`aircrack-ng`, `tcpdump`, `hostapd`, `wireless-regdb`, and related diagnostics). It does not automatically enable monitor mode, transmit packets, deauthenticate clients, crack WPS, or run any capture workflow. Source builds of hcxdumptool/hcxtools are deliberately opt-in through `BUILD_HCX=1` and require explicit network, storage, and CPU time.

## Authentication boundary

The console is local to QEMU/Termux and opens a root shell directly, matching the existing Full v0.3.0 design. There is no shared default password. Do not expose the serial socket or enable a remote login service without creating and testing an intentional authentication policy.

## Rebuild

On a Linux/ARM64-capable build host with the pinned artifacts available:

```sh
./src/build-lite-image.sh guest/alpine-ath9k-v030-lite.img
```

This script is additive and does not edit or invoke the Full `src/build-image.sh` path. The large disk image is distributed as a release asset rather than committed to Git history.

## References

1. [Canonical v0.3.0 Full release](https://github.com/Mohzh344/termux-ath9k-vm/releases/tag/v0.3.0)
2. [Project repository](https://github.com/Mohzh344/termux-ath9k-vm)
