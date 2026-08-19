# termux-ath9k-vm — Full + Lite Unified Bundle

This archive contains the canonical **v0.3.0 Full** VM and the corrected additive **v0.3.1 Lite** VM in one download. Full remains byte-for-byte sourced from the published v0.3.0 release; Lite contains the v0.3.1 fixes and can be selected independently.

## Quick start in Termux

Extract the archive, enter its directory, and install the host dependencies once:

```sh
cd termux-ath9k-vm-full-lite
bash bin/install-termux.sh
bash bin/vm-launcher.sh
```

The unified launcher detects complete Full and Lite bundles. If both are present, it asks which one to use. It does not rebuild, delete, or overwrite a disk image automatically.

For a non-interactive or scripted selection:

```sh
VM_VARIANT=full bash bin/vm-launcher.sh --non-interactive
VM_VARIANT=lite KERNEL_TIER=safe PROFILE=wifi-only bash bin/vm-launcher.sh --non-interactive
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
| **Full** | The original complete v0.3.0 environment with its existing tools, networking, 9p share, and recovery/manual helpers | Alpine `linux-lts` plus initramfs |
| **Lite / safe** | Recommended everyday AR9271/ath9k_htc use on Android with a compatibility-oriented custom kernel and working post-boot apk installation | Direct-root `vmlinuz-safe` |
| **Lite / tiny** | AR9271-only use when the smallest custom kernel is preferred; it now includes the file-locking support required by apk | Direct-root `vmlinuz-tiny` |
| **Lite / lts** | Fallback troubleshooting path if a custom Lite tier does not boot on a particular setup | Lite linux-lts plus initramfs |

Tier A and Tier B are kernel builds, not Wi-Fi monitor-mode switches. Both Lite custom tiers contain the required ath9k_htc, cfg80211, mac80211, XHCI, virtio, ext4, and file-locking support. Wi-Fi operations remain inside the guest and should only be performed on networks and devices you own or are authorized to test.

## USB passthrough

The launcher can list Android-visible USB devices and request permission through Termux:API. For the AR9271, use the direct USB path when the adapter is connected through OTG. If no USB device is selected, the VM starts with a normal console and no passthrough.

The original Full USB wrappers and Lite USB wrappers remain inside their respective nested directories. The unified launcher delegates to those existing low-level paths rather than changing their QEMU or `TERMUX_USB_FD` behavior.

Lite remains offline in `wifi-only` mode. When `ENABLE_NET=1` is set, the guest now brings up the virtio interface with DHCP and uses the QEMU DNS proxy automatically. `install-wifi-tools` refuses clearly when no guest network is available. It uses HTTPS first; if the guest/network path reports a certificate-verification failure, the installer can use its explicitly documented package-signature-checked fallback. Set `APK_ALLOW_INSECURE_FALLBACK=0` to require strict TLS certificate validation.

## Bundle layout

```text
termux-ath9k-vm-full-lite/
├── bin/vm-launcher.sh              # unified recommended entry point
├── bin/vm-launcher-unified.sh      # same dispatcher, explicit name
├── bin/install-termux.sh           # host dependency installer
├── full/                           # canonical Full v0.3.0 bundle, unchanged
│   ├── bin/
│   ├── guest/alpine-ath9k.img
│   └── guest/vmlinuz-lts + initramfs-lts
├── lite/                           # corrected additive Lite v0.3.1 bundle
│   ├── bin/
│   ├── guest/alpine-ath9k-v030-lite.img
│   └── guest/vmlinuz-tiny/safe/lts-lite
└── docs/UNIFIED-RELEASE.md
```

The nested Full launcher and files are copied from the published Full release. The nested Lite launcher and files are copied from the published Lite release. The top-level dispatcher is the only new normal-use layer.

## Advanced and build scripts

The normal boot flow uses only `bin/vm-launcher.sh`. Build, packaging, benchmark, recovery, and low-level launch scripts remain separate so they can be tested and used independently. No build is triggered merely because an image is absent; use the documented build scripts explicitly when preparing a development checkout.

## Integrity

Verify the downloaded archive before extraction using the published `.sha256` file:

```sh
sha256sum -c termux-ath9k-vm-full-lite-ready.tar.gz.sha256
```

This project is intended for authorized wireless testing and general Linux experimentation on hardware and networks for which you have permission.
