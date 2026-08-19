# termux-ath9k-vm — Lite v0.3.3

A lightweight Alpine Linux ARM64 VM companion for Android/Termux and QEMU TCG without KVM. Lite v0.3.3 is an additive corrected image. The original Full v0.3.0 tag remains available unchanged; the unified v0.3.3 archive ships a documented console-shell/PATH patch for its bundled Full guest.

## Quick start

```sh
pkg install -y qemu-system-aarch64-headless termux-api socat e2fsprogs
chmod 700 bin/*.sh src/*.sh
# Recommended: use the unified launcher; it asks whether to grant Internet.
bash ../bin/vm-launcher.sh --lite

# Direct Lite launch remains available:
PROFILE=wifi-only KERNEL_TIER=safe ENABLE_NET=0 ./bin/launch-vm-lite.sh
```

The default Lite console is a private local QEMU serial root login shell started directly by init as `/bin/sh -l`. The `-l` flag only makes BusyBox `ash` read `/etc/profile` and `/etc/profile.d`; it is not a username/password login program. There is no password prompt and no shared default password. The image explicitly keeps `/usr/local/bin` in `PATH`, so commands installed there are available immediately. Do not expose the serial socket or enable remote login without adding a deliberate authentication policy.

## Profiles and tiers

| Profile | RAM | vCPU | Use |
|---|---:|---:|---|
| `wifi-only` | 512 MiB | 1 | Lowest TCG overhead for one external AR9271; offline by default |
| `balanced` | 768 MiB | 2 | Interactive guest package work |
| `default` | 1024 MiB | 2 | General fallback |
| `legacy` | 1536 MiB | 4 | Compatibility fallback |

Use `KERNEL_TIER=tiny` for the smallest custom kernel, `KERNEL_TIER=safe` for the recommended USB insurance options, or `KERNEL_TIER=lts` for the Alpine linux-lts/initramfs fallback. Tier A and Tier B are kernel builds, not monitor-mode switches. Both custom tiers include the file-locking support required by Alpine `apk`.

## Guest networking

Lite stays offline in the default `wifi-only` profile. The unified launcher asks `Grant Internet access to this VM? [y/N]:` after the variant/tier/profile/USB choices. Answer `y` to enable QEMU user networking or `n` to remain offline. For scripted launches, enable it explicitly when package installation is needed:

```sh
ENABLE_NET=1 PROFILE=balanced KERNEL_TIER=safe ./bin/launch-vm-lite.sh
```

When a virtio NIC is present, the guest automatically brings up `eth0`, obtains a DHCP lease, and uses the QEMU DNS proxy at `10.0.2.3`. At every unified or direct Lite launch, QEMU receives the Android/Termux host clock as its RTC base and the launcher executes `date -u -s` inside Alpine after the root prompt, so the guest system clock matches Android even when no `/dev/rtc` device is exposed. If no network interface is available, `install-wifi-tools` stops with an actionable message rather than attempting a guaranteed-to-fail apk transaction.

## USB

For a direct Android USB device path:

```sh
./bin/usb-attach-lite-direct.sh /dev/bus/usb/001/003
```

The AR9271 is expected at USB ID `0cf3:9271`. Android must grant the Termux USB permission. Physical OTG reliability and power behavior still depend on the target phone and adapter.

## Tools after boot

Lite includes the kernel, AR9271 firmware, `iw`, `lsusb`, `kmod`, `ethtool`, `wireless-tools`, and `wifi-diagnose`. It deliberately does not preinstall `aircrack-ng`, `tcpdump`, `hostapd`, `hcxdumptool/hcxtools`, WPS tools, OpenSSH, Python, or compiler packages.

With `ENABLE_NET=1`, install the base runtime set when needed:

```sh
install-wifi-tools
```

The installer uses HTTPS certificate verification first. If the guest/network path reports a certificate-verification failure, it can retry with `apk --check-certificate=no` while Alpine APK package signatures remain enabled. To require strict certificate validation and fail instead of using the fallback:

```sh
APK_ALLOW_INSECURE_FALLBACK=0 install-wifi-tools
```

The installer does not start monitor mode, capture, deauthentication, WPS, injection, or any other security action automatically. `wifite`, `bully`, `reaver`, `kismet`, `hcxdumptool`, and `hcxtools` are not available under those names in the selected Alpine v3.24 repositories; they require a separately reviewed installation path.

## Integrity

Verify the included guest files with:

```sh
cd guest
sha256sum -c SHA256SUMS
```

See `docs/LITE-v0.3.3.md` for the correction details and reproducible rebuild command.
