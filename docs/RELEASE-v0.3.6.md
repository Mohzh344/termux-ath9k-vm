# Release v0.3.6 — Unified Administration and Safer VM Operations

## Summary

v0.3.6 builds on the persistent Full/Lite image design from v0.3.5. It reduces the management surface to one implementation, `bin/vmctl.sh`, while retaining short compatibility wrappers for existing commands. The goal is to make maintenance safer and diagnostics easier without adding a large collection of unrelated scripts.

## Highlights

`vmctl.sh doctor` checks the host architecture, QEMU, ext4 tools, optional Termux USB support, release directories, persistent images, ext4 consistency, and the AR9271 USB signature when Android exposes it. `vmctl.sh info` reports image paths, size, allocation, authentication entry, managed PATH entries, and apk-world count. `vmctl.sh status` reports QEMU processes and image state.

The same command now owns sparse backups, portable export/import, stopped-image resize, persistent PATH management, and USB diagnostics. `vm-backup.sh`, `vm-export.sh`, and `vm-import.sh` remain as compatibility wrappers and contain no second implementation.

An atomic per-image lock protects backup, import, resize, and PATH changes from concurrent modification. Stale locks left by an interrupted process are recoverable after the recorded PID is no longer alive. All image-writing commands continue to require the VM to be stopped.

## User commands

```sh
bash bin/vmctl.sh doctor
bash bin/vmctl.sh info
bash bin/vmctl.sh status
bash bin/vmctl.sh backup --lite
bash bin/vmctl.sh export --lite
bash bin/vmctl.sh import --full /path/to/lite-user-data.tar.gz
bash bin/vmctl.sh resize --lite 3G
bash bin/vmctl.sh path add --lite /opt/my-tool/bin
bash bin/vmctl.sh usb
```

`resize` creates a safety backup, repairs an offline ext4 filesystem when required, grows the sparse image, and validates it. `path add` writes `/etc/profile.d/vmctl-path.sh` inside the persistent image, so the entry survives reboot and release replacement.

## Upgrade notes

The full bootstrap archive is intended for new installations. The thin update archive contains no writable disk images and is intended for users who already have persistent Full/Lite images. Existing users should extract the update archive into a new directory and run:

```sh
VM_LEGACY_DIR="$HOME/old/termux-ath9k-vm-full-lite" bash bin/install-termux.sh
```

If the images already exist under the default `VM_STATE_ROOT`, omit `VM_LEGACY_DIR`. The installer never replaces an existing persistent image.

## Verification

The expanded local test matrix covers launcher detection, Lite `tiny`/`safe`/`lts` image reuse, Full and Lite backup, Full and Lite PATH management, Full and Lite info and doctor reports, Full and Lite resize, active-lock rejection, both export directions, both import targets, path traversal rejection, package-world preservation, and ext4 validation.

The boot matrix covers Full and Lite with `root-console`, `login`, and `login-empty`. The real serial-session test submits a known root password and an empty password to both variants. Archive smoke tests verify first adoption from the full archive and reuse of the same persistent images after installing the thin update archive.

Physical AR9271 OTG passthrough, Android USB permission behavior, and adapter power stability still require testing on the target phone. The sandbox cannot reproduce those Android-side conditions.

## Safety

Use monitor mode and packet transmission only on networks and devices you own or are explicitly authorized to assess. `login-empty` is for a private local console only. The project does not disable apk signatures or include automated credential theft, client disruption, WPS cracking, or unauthorized access.
