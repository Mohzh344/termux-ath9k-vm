# Lite v0.3.4

## Design boundary

Lite v0.3.4 is a small Alpine ARM64 guest for QEMU TCG on Android/Termux without Android root. It is optimized for an external AR9271/ath9k_htc adapter and keeps the console local and passwordless. The ttyAMA0 action starts `/bin/sh -l` directly as root; this is a login shell for profile loading, not a username/password login program. The original Full v0.3.0 tag remains unchanged; the unified v0.3.4 archive applies the documented console-shell/PATH and writable-root patch to its bundled Full guest.

The Lite image contains the kernel, firmware, `iw`, `lsusb`, `kmod`, `ethtool`, `wireless-tools`, and non-destructive diagnostics. Larger wireless runtime tools remain an explicit post-boot installation.

## Corrective changes from v0.3.0 Lite

The tiny and safe custom kernels now build `CONFIG_FILE_LOCKING=y`, which is required by Alpine `apk`. They also embed the signed `regulatory.db` and `regulatory.db.p7s` files so cfg80211 can load the regulatory database before the direct-root filesystem is mounted. The guest init path contains `qemu-net-init`; it only acts when a virtio `eth0` exists, brings the interface up, obtains a DHCP lease, and writes the QEMU DNS proxy. The unified launcher asks after the variant/tier/profile/USB choices whether Internet should be granted; `y` attaches the virtio user network and `n` keeps Lite offline. The default wifi-only profile still has no network device.

The unified launcher reads the Android/Termux host clock with `date -u` on every launch, passes it to QEMU as `-rtc base=...`, waits for the local root console, and executes `date -u -s` inside Alpine before handing the console to the user. The guest console is configured as `ttyAMA0::respawn:/bin/sh -l`, so BusyBox `ash` reads `/etc/profile` and `/etc/profile.d`; `/etc/profile.d/wifi-vm.sh` also explicitly exports the standard `/usr/local/bin` path. The launcher can switch the stopped image to BusyBox `getty` for a normal username/password login or to the explicitly labeled empty-password test mode. This explicit guest-side step is required because the minimal ARM64 kernels do not expose a usable `/dev/rtc` device to userspace. The image builder installs and refreshes the CA bundle after no-script provisioning and places the server trust bundle at `/etc/apk/ca.pem`, the path used by libapk. The installer tries strict certificate verification first. If the guest reports a certificate failure, it can retry with `--check-certificate=no` when `APK_ALLOW_INSECURE_FALLBACK` is not set to `0`; package signatures remain verified by apk. Set that variable to `0` for strict TLS-only behavior.

The builder no longer provisions `binutils`, which was unnecessary for the normal Lite image and was the package involved in the observed aarch64 extraction I/O failure. The builder runs a read-only ext4 consistency check and refuses to package an image that fails `e2fsck -fn`. Its proot calls use `/` as the working directory.

## Profiles

| Profile | RAM | vCPU | Network default | Intended use |
|---|---:|---:|---|---|
| `wifi-only` | 512 MiB | 1 | Disabled | Lowest overhead for USB Wi-Fi |
| `balanced` | 768 MiB | 2 | Disabled unless `ENABLE_NET=1` | Package installation and interactive work |
| `default` | 1024 MiB | 2 | Disabled unless `ENABLE_NET=1` | General fallback |
| `legacy` | 1536 MiB | 4 | Disabled unless `ENABLE_NET=1` | Compatibility fallback |

## Kernel tiers

Tier A (`vmlinuz-tiny`) is the smallest custom kernel with the required AR9271, XHCI, virtio, ext4, serial, and file-locking features. Tier B (`vmlinuz-safe`) adds common USB-serial drivers and is the recommended default. The `lts` choice uses Alpine's linux-lts kernel and initramfs as a compatibility fallback.

Neither tier selects monitor mode or injection mode. Those are guest Wi-Fi operations performed after a physical adapter is passed through and are outside this build-time selection. The embedded regulatory database does not override an adapter's EEPROM restrictions or authorize use of channels outside the applicable local rules.

## Building

The development checkout requires the listed Alpine artifacts, `qemu-aarch64-static`, `proot`, `mke2fs`, `e2fsck`, and an ARM64 kernel source tree for custom tiers. Build the Lite image first so the image builder provides `regulatory.db` and its signature under `GUEST_DIR/rootfs-lite`, then build the custom kernels:

```sh
GUEST_DIR=/path/to/lite-guest \\
./src/build-lite-image.sh /path/to/lite-guest/alpine-ath9k-v030-lite.img

KERNEL_SRC=/path/to/linux-6.18 \\
KERNEL_OUT=/path/to/kernel-build \\
GUEST_DIR=/path/to/lite-guest \\
./src/build-kernel-tiers.sh
```

The kernel builder automatically discovers `GUEST_DIR/rootfs-lite/lib/firmware/regulatory.db` and `regulatory.db.p7s`. If those files are stored elsewhere, provide both `REGDB_SOURCE=/path/to/regulatory.db` and `REGDB_SIG_SOURCE=/path/to/regulatory.db.p7s` explicitly.

The launcher performs the same guest-side time synchronization for Lite `tiny`, `safe`, and `lts` starts. The resulting image must pass:

```sh
e2fsck -fn /path/to/lite-guest/alpine-ath9k-v030-lite.img
```

Do not run the image builder while QEMU has the same image open.

## Installing the Wi-Fi tools

Start the guest with networking enabled. When using the unified launcher, answer `y` at the Internet prompt; for a scripted launch set `ENABLE_NET=1` explicitly:

```sh
ENABLE_NET=1 PROFILE=balanced KERNEL_TIER=safe ./bin/launch-vm-lite.sh
```

Inside the local root console:

```sh
install-wifi-tools
```

The installer installs `aircrack-ng`, `tcpdump`, `hostapd`, `wireless-regdb`, `iw`, `usbutils`, `kmod`, `ethtool`, and `wireless-tools`. It does not start any capture, deauthentication, WPS, injection, or other active wireless operation automatically.

Alpine v3.24 does not provide the package names `wifite`, `bully`, `reaver`, `kismet`, `hcxdumptool`, or `hcxtools` in the selected repositories. They are deliberately not claimed as standard `apk add` packages in this release.

## Authentication

The default `root-console` mode is passwordless by design because it starts a local root shell directly. `AUTH_MODE=login` changes the ttyAMA0 entry to BusyBox `getty` and preserves the existing root password. `AUTH_MODE=login-empty` clears the root password for private local testing only. Full launchers include `rootflags=rw` because Alpine's initramfs otherwise defaults to mounting `/dev/vda` read-only when no rootflags are supplied; this was the root cause of failed Full password changes. Lite's direct ext4 mount is already writable. The `-l` argument only loads shell startup files; it does not invoke `login`, ask for a username, or validate a password in root-console mode. Do not expose the serial socket or add network login without creating an explicit authentication policy.
