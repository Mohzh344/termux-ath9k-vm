# Android Wi-Fi Monitor and Injection Rootless VM

This archive contains the canonical **Full** VM and compact **Lite** VM for running an Alpine Linux ARM64 virtual machine on Android/Termux without Android root. QEMU TCG provides the virtual machine, and the guest can receive an Android-authorized USB adapter such as the Atheros AR9271 through Termux:API.

> **Important status:** The VM boot, persistent-image, and local QEMU paths are testable in the development environment. Physical AR9271 OTG passthrough, Android USB permissions, and adapter power stability must still be verified on the target phone.

## What is new in v0.3.6

The release keeps the v0.3.5 persistent-image design and adds a single host administration interface: `bin/vmctl.sh`. It combines readiness diagnostics, VM information, status, backups, portable export/import, image resizing, persistent PATH management, and Android USB diagnostics. The older `vm-backup.sh`, `vm-export.sh`, and `vm-import.sh` names remain as short compatibility wrappers rather than separate implementations.

The release also adds an atomic image-operation lock. Backup, import, resize, and persistent PATH changes refuse to run concurrently on the same image, and stale locks are recoverable after an interrupted Termux process.

Full and Lite images are adopted into a persistent storage directory on first installation. Updating the archive replaces launchers, scripts, kernels, and documentation without replacing the user's guest image, installed apk packages, PATH files, or `/root` data.

Lite `tiny`, `safe`, and `lts` are kernel choices over the same Lite image. Switching between them does not reinstall packages. For Lite-to-Full or Full-to-Lite migration, the project provides an allow-listed portable export/import flow rather than copying an incompatible filesystem image.

## Quick start in Termux

For the simplest installation or upgrade, use the maintained Python installer. It downloads the latest release metadata, selects the full or thin archive, verifies SHA-256, preserves the external VM data directory, runs the project installer, verifies the resulting launchers, and removes the old checkout only after successful installation:

```sh
curl -fL https://raw.githubusercontent.com/Mohzh344/android-wifi-monitor-injection-rootless/main/tools/install_android_wifi_vm.py \
  -o install_android_wifi_vm.py
chmod +x install_android_wifi_vm.py
python3 install_android_wifi_vm.py
```

The normal command asks before deleting an existing checkout. To select a custom location and automatically approve deletion after successful installation:

```sh
python3 install_android_wifi_vm.py \
  --project-dir "$HOME/android-wifi-monitor-injection-rootless" \
  --state-dir "$HOME/.local/share/android-wifi-monitor-injection-rootless" \
  --yes
```

Use `--dry-run` to inspect the latest release and paths without downloading or changing anything. Use `--download-only` to download and verify an archive without extracting, installing, or deleting anything. The script cannot change the parent shell's current directory; after it completes, enter the new checkout explicitly with `cd` as shown in its output.

For manual installation, download an archive from the [latest GitHub Release](https://github.com/Mohzh344/android-wifi-monitor-injection-rootless/releases/latest). Choose the full archive for a new installation and the smaller update archive when a persistent Full/Lite image already exists:

| Archive | Intended user | Contains writable images? |
|---|---|---:|
| `termux-ath9k-vm-v036-full-lite-ready.tar.gz` | New installation or migration from an older checkout | Yes, for first adoption |
| `termux-ath9k-vm-v036-update.tar.gz` | Existing v0.3.x installation | No; it preserves storage and saves about 290 MB of compressed download |

For a new installation, verify the published checksum and extract the full archive into a new directory:

```sh
sha256sum -c termux-ath9k-vm-v036-full-lite-ready.tar.gz.sha256
mkdir -p "$HOME/android-wifi-vm-v036"
tar --sparse -xzf termux-ath9k-vm-v036-full-lite-ready.tar.gz \
  -C "$HOME/android-wifi-vm-v036" --strip-components=1
cd "$HOME/android-wifi-vm-v036"
```

Install host dependencies once:

```sh
bash bin/install-termux.sh
```

The installer creates the persistent storage directory and adopts any bundled Full/Lite image that does not already have a persistent copy. It never overwrites an existing persistent image. Check the installation before launching with:

```sh
bash bin/vmctl.sh doctor
bash bin/vmctl.sh info
```

Start the recommended launcher with:

```sh
bash bin/vm-launcher.sh
```

The launcher detects Full and Lite, asks which variant to use, offers the Lite kernel tier, asks whether the guest may use the Internet, synchronizes the guest clock from Android at every launch, handles console authentication, and optionally requests Android USB permission.

## Persistent storage and safe upgrades

By default, writable images are stored outside the release directory:

```text
$XDG_DATA_HOME/android-wifi-monitor-injection-rootless/
  full/alpine-ath9k.img
  lite/alpine-ath9k-v030-lite.img
  backups/
  exports/
```

When `XDG_DATA_HOME` is not set, the default is:

```text
$HOME/.local/share/android-wifi-monitor-injection-rootless/
```

The location can be changed explicitly before running the installer or launcher:

```sh
export VM_STATE_ROOT="$HOME/android-wifi-vm-data"
bash bin/install-termux.sh
bash bin/vm-launcher.sh
```

The first installer run with the full archive moves or sparsely copies the bundled images into this directory. The thin update archive has no disk image by design and reuses the existing persistent image. Subsequent archives do not replace an existing image. The release directory can therefore be removed or replaced after the installer reports successful adoption.

For an existing installation, extract the thin update archive into a different directory and run the installer before deleting the old checkout:

```sh
mkdir -p "$HOME/android-wifi-vm-v036-update"
tar --sparse -xzf termux-ath9k-vm-v036-update.tar.gz \
  -C "$HOME/android-wifi-vm-v036-update" --strip-components=1
cd "$HOME/android-wifi-vm-v036-update"
VM_LEGACY_DIR="$HOME/old/termux-ath9k-vm-full-lite" \
  bash bin/install-termux.sh
```

If the old image was already adopted into the default storage directory, omit `VM_LEGACY_DIR`; the installer will keep that image and update only the release files.

### Existing v0.3.4 or older checkout

Extract the full or thin update archive into a different directory. Before deleting the old checkout, run the installer from the new directory and point it at the old one:

```sh
cd "$HOME/android-wifi-vm-v036"
VM_LEGACY_DIR="$HOME/old/termux-ath9k-vm-full-lite" \
  bash bin/install-termux.sh
```

The old checkout must contain `full/` and/or `lite/` with their guest image files. The installer adopts each image only when the corresponding persistent image is absent. It does not copy or overwrite a persistent image that already exists.

For isolated legacy/debug behavior, disable the storage layer explicitly:

```sh
VM_STORAGE_ENABLED=0 bash bin/vm-launcher.sh --lite --dry-run --non-interactive
```

## Administration, backups, and migration

Use the single administration command for maintenance. The VM must be stopped for operations that write an image:

```sh
bash bin/vmctl.sh doctor             # host, release, storage, and USB readiness
bash bin/vmctl.sh info               # image size, auth entry, PATH entries, apk count
bash bin/vmctl.sh status             # running QEMU processes and image state
bash bin/vmctl.sh backup --lite
bash bin/vmctl.sh backup --full
```

A backup is a sparse-aware copy of a complete Full or Lite image. The image lock prevents another management operation from changing the same image during the copy. The old commands `bin/vm-backup.sh`, `bin/vm-export.sh`, and `bin/vm-import.sh` still work and call `vmctl.sh` internally.

The auth configurator and importer also create safety backups by default. Never edit an image with `debugfs`, `e2fsck`, or a migration command while QEMU is using it.

A portable export is smaller and better for moving a working environment between variants. It contains `/root`, `/home`, `/opt`, `/usr/local`, `/etc/profile.d`, and `/etc/apk/world`:

```sh
bash bin/vmctl.sh export --lite
bash bin/vmctl.sh export --full
```

Import it into a stopped target image:

```sh
bash bin/vmctl.sh import --full /path/to/lite-user-data-YYYYMMDDTHHMMSSZ.tar.gz
bash bin/vmctl.sh import --lite /path/to/full-user-data-YYYYMMDDTHHMMSSZ.tar.gz
```

The importer restores user files, local tools, persistent PATH files, and the explicitly requested apk package list. It writes the package list to `/root/.vm-migration/apk-world` and creates:

```sh
/root/.vm-migration/apply-packages.sh
```

Boot the target with Internet access only when needed, then run that helper as root:

```sh
/root/.vm-migration/apply-packages.sh
```

The helper uses the target's apk repositories and signatures. It does not copy packages blindly from the old filesystem, and it does not disable apk signature verification.

Authentication databases, `/etc/inittab`, apk repositories, kernels, firmware, and `/lib/modules` are intentionally excluded from portable exports. Reconfigure `root-console`, `login`, or `login-empty` with the launcher instead of copying `/etc/shadow` or `/etc/passwd` between images.

Export archives can contain private files from `/root`. Store them securely and delete them when they are no longer needed.

### Image size and persistent PATH management

When an image needs more room, grow it only while the VM is stopped. The command creates a safety backup, checks ext4, grows the sparse file, and validates the result:

```sh
bash bin/vmctl.sh resize --lite 3G
bash bin/vmctl.sh resize --full 4G
```

To persist a custom tool directory without manually editing `/etc/profile`, use:

```sh
bash bin/vmctl.sh path add --lite /opt/my-tool/bin
bash bin/vmctl.sh path add --full /usr/local/custom/bin
bash bin/vmctl.sh path list --lite
```

The managed PATH file is stored inside the guest at `/etc/profile.d/vmctl-path.sh`, is loaded by the login shell, and remains in the persistent image across reboot and release updates. The command refuses to edit an image while QEMU is using it.

## Selecting Full, Lite, and kernel tiers

| Choice | Use case | Image behavior |
|---|---|---|
| **Full** | The complete environment with its original v0.3.0 guest lineage, Linux LTS kernel/initramfs, networking, and broader utilities | Uses persistent Full image |
| **Lite / safe** | Recommended everyday AR9271 use with the compatibility-oriented custom kernel | Uses the shared persistent Lite image |
| **Lite / tiny** | Smallest custom kernel for an AR9271-focused setup | Uses the same Lite image as safe |
| **Lite / lts** | Fallback troubleshooting kernel and initramfs | Uses the same Lite image as safe |

The Lite tiers are not monitor-mode switches. They are different boot kernels. Wireless operations remain inside the Alpine guest and require a compatible adapter and authorized network.

## Launcher examples

Interactive use:

```sh
bash bin/vm-launcher.sh
```

Non-interactive Full with direct root console and no guest Internet:

```sh
VM_VARIANT=full AUTH_MODE=root-console ENABLE_NET=0 \
  bash bin/vm-launcher.sh --non-interactive
```

Non-interactive Lite safe with Internet disabled:

```sh
VM_VARIANT=lite KERNEL_TIER=safe PROFILE=wifi-only \
  AUTH_MODE=root-console ENABLE_NET=0 \
  bash bin/vm-launcher.sh --non-interactive
```

A dry run prints selection and the persistent disk without starting QEMU:

```sh
bash bin/vm-launcher.sh --full --dry-run --non-interactive
bash bin/vm-launcher.sh --lite --dry-run --non-interactive
```

## Console authentication

`root-console` is the recommended local mode. It starts `/bin/sh -l` directly as root, reads `/etc/profile` and `/etc/profile.d`, and does not ask for a username or password.

`login` uses BusyBox `getty` and a normal username/password prompt. `login-empty` intentionally clears the root password for private local testing only. Do not combine `login-empty` with Internet access or an untrusted console.

The `-l` in `/bin/sh -l` means login shell; it does not invoke a password login manager. It is what makes persistent PATH files load in the direct root console. A PATH added with `export PATH=...` in one shell remains temporary. A PATH written to `/etc/profile.d/tool-name.sh` remains available after reboot and in both root-console and normal login modes.

## USB diagnostics and passthrough for AR9271

Before troubleshooting passthrough, run the non-destructive host diagnostic:

```sh
bash bin/vmctl.sh usb
bash bin/vmctl.sh doctor
```

The diagnostic checks Termux:API visibility, `0cf3:9271`, QEMU, and `socat`. It does not grant permission or start QEMU; the launcher remains responsible for requesting Android USB permission.

Connect the adapter through OTG and let Android expose it to Termux:

```sh
termux-usb -l
```

The unified launcher can select an Android-visible device and request permission. For the AR9271, the direct QEMU path matches USB ID `0cf3:9271`:

```sh
bash bin/vm-launcher.sh
```

Inside Alpine, verify the adapter non-destructively:

```sh
wifi-diagnose
lsusb
iw dev
```

Seeing the device in `lsusb` alone does not prove that `ath9k_htc` loaded or that firmware was found. Direct passthrough is attempted first; the optional usb-redir wrapper remains available for compatibility testing.

If OTG disconnects repeatedly, test a short high-quality OTG cable and a charge-through/Y-OTG arrangement with an appropriate 5 V source. The guest cannot repair an Android-side power or permission reset.

## Internet and clock policy

The launcher asks for guest Internet access on every interactive run. `ENABLE_NET=1` enables QEMU user networking and DHCP; `ENABLE_NET=0` keeps the guest offline. The non-interactive default is Full online for historical compatibility and Lite offline; set `ENABLE_NET` explicitly in scripts.

QEMU receives an RTC base from the Android/Termux clock, and the launcher explicitly synchronizes Alpine's system clock after the console becomes ready. Set `TIME_SYNC=0` only for deterministic debugging.

## Rebuilding

Rebuilding is optional. On a supported Linux/ARM64-capable build host:

```sh
./src/download-artifacts.sh
./src/build-image.sh
```

The combined release packager for this feature is:

```sh
./src/package-v036-unified-release.sh
```

It expects the pinned Full/Lite build inputs described by its environment variables and emits a sparse-aware archive plus checksum. Set `INCLUDE_IMAGES=0` and choose an update output path to build the thin archive for existing users. The original `v0.3.0` Full release remains a historical source and is not rewritten by this feature.

## Project layout

| Path | Purpose |
|---|---|
| `tools/install_android_wifi_vm.py` | Verified fresh-install and upgrade helper for Termux |
| `bin/vm-launcher.sh` | Recommended Full/Lite dispatcher using persistent images |
| `bin/vm-launcher-unified.sh` | Compatibility wrapper for the main dispatcher |
| `bin/vm-launcher-legacy.sh` | Preserved pre-storage launcher for advanced legacy use |
| `bin/vmctl.sh` | Unified doctor, info, status, backup, export, import, resize, PATH, and USB administration |
| `bin/vm-backup.sh`, `vm-export.sh`, `vm-import.sh` | Compatibility wrappers that call `vmctl.sh` |
| `src/vm-storage-lib.sh` | Shared adoption, lock, backup, and ext4 helpers |
| `src/install-termux-unified.sh` | Host dependency installer and image adoption step |
| `src/configure-console-auth.sh` | Offline auth-mode change with backup and ext4 validation |
| `src/test-unified-launcher.sh` | Launcher detection and selection tests |
| `src/test-migration-debug.sh` | Real sparse-image export/import test fixture |
| `src/test-auth-boot-matrix.sh` | Full/Lite boot matrix for all three auth modes |
| `src/test-login-sessions.sh` | Real serial-session credential test |
| `src/package-v036-unified-release.sh` | v0.3.6 full and thin release packager |
| `docs/RELEASE-v0.3.6.md` | v0.3.6 migration and verification notes |
| `src/test-persistent-storage.sh` | Full/Lite persistent storage and vmctl administration matrix |

## Safety and legal use

Use monitor mode and packet transmission only on networks and devices that you own or are explicitly authorized to assess. This project does not include automated credential theft, client disruption, WPS cracking, or unauthorized access. Regulatory-domain and transmit-power limits must not be bypassed.

## References

[1] [QEMU ARM `virt` machine documentation](https://www.qemu.org/docs/master/system/arm/virt.html) — virtual ARM machine configuration used by the launchers.

[2] [Termux:API project](https://github.com/termux/termux-api) — Android-facing APIs used for USB permission and host clock integration.

[3] [Alpine Package Keeper (`apk`) documentation](https://wiki.alpinelinux.org/wiki/Alpine_Package_Keeper) — package installation and signature-preserving migration behavior.

[4] [Project repository](https://github.com/Mohzh344/android-wifi-monitor-injection-rootless) — source, release assets, and issue tracker.
