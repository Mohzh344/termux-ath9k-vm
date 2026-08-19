# termux-ath9k-vm — Full + Lite Unified Bundle

This archive contains the canonical **v0.3.0 Full** VM and the corrected additive **v0.3.4 Lite** VM in one download. The v0.3.4 release keeps the original v0.3.0 tag available while applying the console-shell/PATH correction and writable-root fix to the bundled Full guest.

## Quick start in Termux

Extract the archive, enter its directory, and install the host dependencies once:

```sh
cd termux-ath9k-vm-full-lite
bash bin/install-termux.sh
bash bin/vm-launcher.sh
```

The unified launcher detects complete Full and Lite bundles. If both are present, it asks which one to use, then offers console authentication modes, and asks `Grant Internet access to this VM? [y/N]:`. The recommended `root-console` mode starts `/bin/sh -l` directly as root; `login` selects BusyBox `getty` for a username/password prompt using the existing root password; `login-empty` clears root's password for private local testing only. The `-l` flag only reads `/etc/profile` and `/etc/profile.d`; it does not invoke `/sbin/login`. The launcher also seeds QEMU's RTC from the Android/Termux host clock and explicitly runs `date -u -s` inside the guest after the local root prompt at every launch. It does not rebuild, delete, or overwrite a disk image automatically.

For a non-interactive or scripted selection:

```sh
VM_VARIANT=full AUTH_MODE=root-console bash bin/vm-launcher.sh --non-interactive
VM_VARIANT=full AUTH_MODE=login ENABLE_NET=0 bash bin/vm-launcher.sh --non-interactive
VM_VARIANT=lite KERNEL_TIER=safe PROFILE=wifi-only AUTH_MODE=root-console ENABLE_NET=0 bash bin/vm-launcher.sh --non-interactive
# Private local testing only:
VM_VARIANT=lite AUTH_MODE=login-empty ENABLE_NET=0 bash bin/vm-launcher.sh --non-interactive
```

Use `--dry-run` to verify detection and the selected settings without starting QEMU:

```sh
bash bin/vm-launcher.sh --dry-run
bash bin/vm-launcher.sh --full --dry-run
bash bin/vm-launcher.sh --lite --dry-run
```

## Which variant should I use?

| Variant | Best for | Kernel path |
|---|---|---|
| **Full** | The original complete v0.3.0 environment with its existing tools, networking, 9p share, and recovery/manual helpers; v0.3.4 adds writable root mounting for password changes | Alpine `linux-lts` plus initramfs |
| **Lite / safe** | Recommended everyday AR9271/ath9k_htc use on Android with a compatibility-oriented custom kernel, working post-boot apk installation, and direct login-shell PATH | Direct-root `vmlinuz-safe` |
| **Lite / tiny** | AR9271-only use when the smallest custom kernel is preferred; it now includes the file-locking support required by apk | Direct-root `vmlinuz-tiny` |
| **Lite / lts** | Fallback troubleshooting path if a custom Lite tier does not boot on a particular setup | Lite linux-lts plus initramfs |

Tier A and Tier B are kernel builds, not Wi-Fi monitor-mode switches. Both Lite custom tiers contain the required ath9k_htc, cfg80211, mac80211, XHCI, virtio, ext4, and file-locking support. Wi-Fi operations remain inside the guest and should only be performed on networks and devices you own or are authorized to test.

## USB passthrough

The launcher can list Android-visible USB devices and request permission through Termux:API. For the AR9271, use the direct USB path when the adapter is connected through OTG. If no USB device is selected, the VM starts with a normal console and no passthrough.

The original Full USB wrappers and Lite USB wrappers remain inside their respective nested directories. The unified launcher delegates to those existing low-level paths rather than changing their QEMU or `TERMUX_USB_FD` behavior.

After the variant, Lite tier/profile, and USB choices, the launcher asks whether to grant Internet access. `y` sets `ENABLE_NET=1`; `n` sets `ENABLE_NET=0`. In non-interactive mode, Full preserves its historical online default while Lite remains offline unless `ENABLE_NET=1` is supplied. When `ENABLE_NET=1` is set, the guest brings up the virtio interface with DHCP and uses the QEMU DNS proxy automatically. `install-wifi-tools` refuses clearly when no guest network is available. It uses HTTPS first; if the guest/network path reports a certificate-verification failure, the installer can use its explicitly documented package-signature-checked fallback. Set `APK_ALLOW_INSECURE_FALLBACK=0` to require strict TLS certificate validation. At every launch, QEMU receives `RTC_BASE` from the Android/Termux clock and the adapter explicitly runs `date -u -s` inside Alpine after the root console is ready, so the guest system clock matches Android even when no `/dev/rtc` device is exposed by the minimal ARM64 kernel.

## Bundle layout

```text
termux-ath9k-vm-full-lite/
├── bin/vm-launcher.sh              # unified recommended entry point
├── bin/vm-launcher-unified.sh      # same dispatcher, explicit name
├── bin/launch-vm-full-unified.sh   # Full adapter for RTC and optional Internet
├── bin/install-termux.sh           # host dependency installer
├── full/                           # Full v0.3.0 guest plus documented v0.3.4 adapter patch
│   ├── bin/
│   ├── guest/alpine-ath9k.img
│   └── guest/vmlinuz-lts + initramfs-lts
├── lite/                           # corrected additive Lite v0.3.4 bundle
│   ├── bin/
│   ├── guest/alpine-ath9k-v030-lite.img
│   └── guest/vmlinuz-tiny/safe/lts-lite
└── docs/UNIFIED-RELEASE.md
```

The nested Full guest is sourced from the published Full release, then receives the documented console-shell/PATH patch and the v0.3.4 writable-root launcher fix. The original Full tag remains unchanged; the bundled Full image is intentionally patched so `passwd` can persist changes. The Lite guest is patched and its builder/source script is updated equivalently. The top-level dispatcher offers explicit authentication modes, the optional Internet prompt, and Android-clock RTC seeding.

## Advanced and build scripts

The normal boot flow uses only `bin/vm-launcher.sh`. Build, packaging, benchmark, recovery, and low-level launch scripts remain separate so they can be tested and used independently. No build is triggered merely because an image is absent; use the documented build scripts explicitly when preparing a development checkout.

## Integrity

Verify the downloaded archive before extraction using the published `.sha256` file:

```sh
sha256sum -c termux-ath9k-vm-full-lite-ready.tar.gz.sha256
```

This project is intended for authorized wireless testing and general Linux experimentation on hardware and networks for which you have permission.
