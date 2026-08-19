# Unified Full + Lite Release

## Scope

The unified archive is an additive distribution layer. It contains the published Full v0.3.0 guest under `full/` with the v0.3.3 console-shell/PATH patch and the corrected Lite v0.3.3 guest under `lite/`. The top-level `bin/vm-launcher.sh` detects complete bundles, asks whether Internet should be granted, seeds the Android clock, and delegates to the appropriate launch path.

The Full and Lite guest images, kernels, initramfs files, QEMU command lines, and nested low-level launchers are not merged into one VM. They remain independent so the user can choose either environment without losing the other.

## Detection contract

A Full bundle is complete when it contains:

```text
guest/alpine-ath9k.img
guest/vmlinuz-lts
guest/initramfs-lts
```

A Lite bundle is complete when it contains:

```text
guest/alpine-ath9k-v030-lite.img
guest/vmlinuz-tiny
guest/vmlinuz-safe
guest/vmlinuz-lts-lite
guest/initramfs-lts-lite
```

The dispatcher first respects explicit environment variables and command-line selection. It automatically selects a single complete bundle, asks when both complete bundles are available, and fails safely when no complete bundle is available or the mode is non-interactive and ambiguous.

## Compatibility boundary

The existing Full release remains available at the original `v0.3.0` tag and release. The combined release does not replace that tag. Its nested `full/` directory is sourced from the published Full archive and receives only the documented v0.3.3 image patch: `ttyAMA0` starts `/bin/sh -l` directly as root, and `/etc/profile` keeps the standard executable PATH. Its nested `lite/` directory contains the v0.3.3 Lite image, file-locking custom kernels, automatic DHCP setup, corrected apk installer, and default time synchronization. The patch does not invoke `login`, `getty`, SSH, or password validation.

After variant, tier/profile, and USB selection, the launcher asks `Grant Internet access to this VM? [y/N]:`. `y` attaches QEMU user networking and sets `ENABLE_NET=1`; `n` keeps the guest offline. Lite is offline by default in non-interactive mode. With `ENABLE_NET=1`, guest init configures DHCP and the QEMU DNS proxy. At every launch, the dispatcher passes `RTC_BASE` and the adapter executes `date -u -s` inside Alpine after root prompt, so the guest system clock matches Android without requiring NTP. The Wi-Fi installer validates network availability, tries HTTPS certificate validation first, and can use an explicitly reported package-signature-checked fallback controlled by `APK_ALLOW_INSECURE_FALLBACK=0`.

## Build behavior

The launcher never downloads, rebuilds, resizes, deletes, or repairs a disk image merely because detection fails. Preparation remains an explicit developer operation through the existing build and packaging scripts. The Lite builder emits the direct `/bin/sh -l` console entry and explicit PATH. `src/patch-console-login-shell.sh` applies the same change offline to an existing ext4 guest image and refuses to edit an image while QEMU is running. The builder removes the unnecessary `binutils` provisioning step, uses a stable proot working directory, regenerates the CA bundle, and rejects an ext4 image that fails `e2fsck -fn`.

## Hardware verification boundary

Dry-run and mock tests can verify detection, argument precedence, and delegation. Actual Android OTG permission handling and AR9271 passthrough must still be verified on the target phone with Termux:API and the adapter connected.
