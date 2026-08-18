# termux-ath9k-vm — v0.3.0-lite

A lightweight Alpine Linux ARM64 VM companion for Android/Termux and QEMU TCG without KVM. This is an additive Lite image; the existing `v0.3.0` Full release remains the canonical full-tool distribution.

## Quick start

```sh
pkg install -y qemu-system-aarch64-headless termux-api socat e2fsprogs
chmod 700 bin/*.sh src/*.sh
PROFILE=wifi-only KERNEL_TIER=safe ./bin/launch-vm-lite.sh
```

The default Lite console is a private local QEMU serial root shell. There is no password prompt and no shared default password. Do not expose the serial socket or enable remote login without adding a deliberate authentication policy.

## Profiles

| Profile | RAM | vCPU | Use |
|---|---:|---:|---|
| `wifi-only` | 512 MiB | 1 | Lowest TCG overhead for one external AR9271 |
| `balanced` | 768 MiB | 2 | Interactive guest package work |
| `default` | 1024 MiB | 2 | General fallback |
| `legacy` | 1536 MiB | 4 | Compatibility fallback |

Use `KERNEL_TIER=tiny` for the smallest custom kernel, `KERNEL_TIER=safe` for the recommended USB insurance options, or `KERNEL_TIER=lts` for the Alpine linux-lts/initramfs fallback.

## USB

For a direct Android USB device path:

```sh
./bin/usb-attach-lite-direct.sh /dev/bus/usb/001/003
```

The AR9271 is expected at USB ID `0cf3:9271`. Android must grant the Termux USB permission. Physical OTG reliability and power behavior still depend on the target phone and adapter.

## Tools after boot

Lite includes the kernel, AR9271 firmware, `iw`, `lsusb`, `kmod`, `ethtool`, `wireless-tools`, and `wifi-diagnose`. It deliberately does not preinstall aircrack-ng, tcpdump, hostapd, hcxdumptool/hcxtools, WPS tools, OpenSSH, Python, or compiler packages.

Install the base optional runtime set only when needed:

```sh
install-wifi-tools
```

The installer does not start monitor mode, capture, deauthentication, WPS, or any other security action automatically. Source builds require explicit `BUILD_HCX=1` and additional guest resources.

## Integrity

Verify the included guest files with:

```sh
cd guest
sha256sum -c SHA256SUMS
```

See `docs/LITE-v0.3.0.md` for the design boundary and reproducible rebuild command.
