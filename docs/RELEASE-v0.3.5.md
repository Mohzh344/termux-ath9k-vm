# Release v0.3.5 — Persistent VM Data and Migration

## Summary

v0.3.5 separates release files from writable guest data. The release provides a full bootstrap archive for new installations and a thin update archive for existing installations. Both can update launchers, scripts, kernels, and documentation without replacing the user's Full or Lite disk image. The change is designed for rootless Android/Termux installations where reinstalling packages and rebuilding a guest image is expensive in time and storage.

## Highlights

The full bootstrap archive adopts its bundled Full and Lite images into a persistent data directory on first installation. The thin update archive intentionally contains no writable disk image; it reuses an existing persistent image or adopts one from `VM_LEGACY_DIR`. Later launches use the persistent images automatically. Lite `tiny`, `safe`, and `lts` continue to share one image, so changing Lite kernel tiers preserves installed packages and files.

`vm-backup.sh` creates sparse-aware image backups and refuses to modify a running image. `vm-export.sh` creates a portable migration archive containing user data, persistent PATH files, local tools, and `/etc/apk/world`. `vm-import.sh` restores that allow-listed data into a stopped Full or Lite image, creates a safety backup, and writes a guest-side package-apply helper.

The migration deliberately excludes authentication databases, init configuration, repositories, kernels, firmware, and kernel modules. These are image- or release-specific and must not be copied blindly between Full and Lite. Package installation remains controlled by apk, with package signatures enabled.

The unified launcher now treats the persistent image as the runtime disk while retaining `VM_STORAGE_ENABLED=0` for isolated legacy/debug runs. The legacy single-bundle launcher is preserved as `vm-launcher-legacy.sh`.

## Upgrade notes

For a new installation, use `termux-ath9k-vm-v035-full-lite-ready.tar.gz`. For an existing v0.3.x installation, use `termux-ath9k-vm-v035-update.tar.gz`; it is approximately 290 MB smaller in compressed form because it excludes the disk images. Extract it into a new directory, verify its checksum, and run the installer before removing an old checkout:

```sh
VM_LEGACY_DIR="$HOME/old/termux-ath9k-vm-full-lite" bash bin/install-termux.sh
```

The same command works with the full archive when migrating from an older checkout. If the old image was already adopted into persistent storage, omit `VM_LEGACY_DIR`. If the old checkout contains Full and Lite directories, the installer adopts them into persistent storage. If the persistent image already exists, it is never replaced by a newly extracted image. The old checkout can be removed only after the installer reports the persistent storage path.

For a Lite-to-Full migration:

```sh
./bin/vm-export.sh --lite
./bin/vm-import.sh --full /path/to/lite-user-data.tar.gz
```

Boot Full with Internet enabled and run `/root/.vm-migration/apply-packages.sh` to reinstall explicitly requested apk packages. Kernel modules and hardware-specific packages are not silently forced into the target; review any package failure and install a target-compatible package manually.

## Verification boundary

Local tests cover persistent image adoption, repeated launcher detection, Lite-to-Full portable export/import, automatic import backup, PATH-file restoration, apk-world preservation, archive path traversal rejection, and read-only ext4 consistency checks. Physical AR9271 OTG passthrough still requires validation on the target Android phone because the build environment cannot reproduce Android USB permissions or real adapter power behavior.

## Safety

Use the wireless capabilities only on networks and devices you own or are explicitly authorized to assess. Export archives may contain private files from `/root`; keep them protected. Do not enable `login-empty` or Internet access for an untrusted environment.
