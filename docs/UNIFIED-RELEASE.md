# Unified Full + Lite Release

## Scope

The unified archive is an additive distribution layer. It contains the published Full v0.3.0 bundle under `full/` unchanged and the corrected Lite v0.3.1 bundle under `lite/`. The top-level `bin/vm-launcher.sh` detects complete bundles and delegates to the appropriate existing launcher.

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

The existing Full release remains available at the original `v0.3.0` tag and release. The combined release does not replace that tag. Its nested `full/` directory is a copy of the published Full archive, while its nested `lite/` directory contains the rebuilt v0.3.1 Lite image, file-locking custom kernels, automatic DHCP setup, and corrected apk installer. The new top-level dispatcher and installer remain the convenience layer added by this release.

Lite is offline in the default `wifi-only` profile. With `ENABLE_NET=1`, guest init configures DHCP and the QEMU DNS proxy. The Wi-Fi installer validates network availability, tries HTTPS certificate validation first, and can use an explicitly reported package-signature-checked fallback controlled by `APK_ALLOW_INSECURE_FALLBACK=0`.

## Build behavior

The launcher never downloads, rebuilds, resizes, deletes, or repairs a disk image merely because detection fails. Preparation remains an explicit developer operation through the existing build and packaging scripts. The Lite builder removes the unnecessary `binutils` provisioning step, uses a stable proot working directory, regenerates the CA bundle, and rejects an ext4 image that fails `e2fsck -fn`.

## Hardware verification boundary

Dry-run and mock tests can verify detection, argument precedence, and delegation. Actual Android OTG permission handling and AR9271 passthrough must still be verified on the target phone with Termux:API and the adapter connected.
