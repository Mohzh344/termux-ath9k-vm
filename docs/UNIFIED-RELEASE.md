# Unified Full + Lite Release

## Scope

The unified archive contains the canonical Full VM under `full/` and compact Lite VM under `lite/`. The top-level launcher detects complete bundles, offers explicit console authentication modes, asks whether Internet should be granted, seeds the Android clock, and delegates to the appropriate launch path.

The Full and Lite guest images, kernels, initramfs files, QEMU command lines, and nested low-level launchers remain independent. The user can choose either environment without losing the other.

## Installation and updates

`install.sh` is the general bootstrap installer for a new user. It creates the short `$HOME/awvm` project directory, downloads and verifies the full archive, and runs the host installer. `bin/awvm-update.sh` is used from an existing checkout; it downloads and verifies the thin update archive, preserves external VM data, and replaces the checkout only after installation succeeds.

The default new persistent data directory is `$HOME/.local/share/awvm`. Existing v0.3.5/v0.3.6 data under `$HOME/.local/share/android-wifi-monitor-injection-rootless` is preferred automatically for compatibility. `VM_STATE_ROOT` can override either location.

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

## Persistent data and administration

The writable Full and Lite images are adopted into `VM_STATE_ROOT` and are not replaced by later archives. Lite `tiny`, `safe`, and `lts` use one shared image. `bin/vmctl.sh` provides diagnostics, information, status, sparse backup, portable export/import, stopped-image resize, persistent PATH management, and USB diagnostics. An atomic image-operation lock prevents concurrent writes to the same image.

## Compatibility boundary

The original Full release remains available at the original `v0.3.0` tag and release. The unified release does not replace that tag. Its nested `full/` directory is sourced from the published Full archive and receives the documented console-shell, PATH, writable-root, and `rootflags=rw` patches. Its nested `lite/` directory contains the compact guest, file-locking custom kernels, automatic DHCP setup, corrected apk installer, and default time synchronization.

After variant selection, the launcher offers `root-console` (recommended), `login` (existing root password), or `login-empty` (private testing only), then asks whether Internet should be granted. With `ENABLE_NET=1`, guest init configures DHCP and QEMU user networking. At every launch, the dispatcher passes `RTC_BASE` and the adapter synchronizes the Alpine system clock from Android. The Wi-Fi installer keeps apk package signatures enabled.

## Build behavior

The launcher never downloads, rebuilds, resizes, deletes, or repairs a disk image merely because detection fails. Preparation remains an explicit developer operation through the build and packaging scripts. The Lite builder emits the direct `/bin/sh -l` console entry and explicit PATH. `src/patch-console-login-shell.sh` applies the same change offline to an existing ext4 guest image, while `src/configure-console-auth.sh` switches a stopped image between direct root and getty modes and refuses to edit a live image.

## Hardware verification boundary

Dry-run, mock, and sparse-image tests verify detection, argument precedence, administration, migration, update safety, and delegation. Actual Android OTG permission handling, AR9271 passthrough, and adapter power stability must still be verified on the target phone with Termux:API and the adapter connected.
