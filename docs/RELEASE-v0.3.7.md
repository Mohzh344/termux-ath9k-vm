# Release v0.3.7 — Simple Bootstrap and Bundled Updates

## Overview

v0.3.7 keeps the persistent Full/Lite VM data model and unified `vmctl.sh` administration from v0.3.6. It replaces the previous Python bootstrap helper with two small, purpose-specific shell entry points designed for Termux.

`install.sh` is the general installer for a new user who has no project checkout. It installs the small bootstrap prerequisites, reads the latest GitHub Release, downloads the full Full/Lite archive, verifies its published SHA-256, extracts it into `$HOME/awvm`, and runs the bundled host installer.

`bin/awvm-update.sh` is included in every release and is used by an existing user from inside the current checkout. It checks the latest release, downloads the thin update archive, verifies its SHA-256, runs the new installer while the current checkout is still available for legacy image adoption, and replaces the checkout only after success. It preserves the external VM state directory and does not reinstall or replace the guest images.

## Short paths

The default new project directory is:

```text
$HOME/awvm
```

The default new persistent data directory is:

```text
$HOME/.local/share/awvm
```

An existing v0.3.5/v0.3.6 data directory at `$HOME/.local/share/android-wifi-monitor-injection-rootless` is detected first for compatibility. Set `VM_STATE_ROOT` to choose a different location. Never place the persistent data directory inside a checkout that will be replaced.

## New installation

Install the bootstrap dependencies and run the public installer:

```sh
pkg update -y
pkg install -y bash curl tar coreutils
curl -fL https://raw.githubusercontent.com/Mohzh344/android-wifi-monitor-injection-rootless/main/install.sh -o install.sh
bash install.sh
```

The installer refuses to overwrite an existing `$HOME/awvm` directory. It verifies the archive before extraction and checks that `bin/install-termux.sh`, `bin/vm-launcher.sh`, and `bin/vmctl.sh` exist after installation.

## Existing installation update

Run the updater from the existing project:

```sh
cd "$HOME/awvm"
bash bin/awvm-update.sh
```

The updater uses the thin archive, so the large writable disk images are not downloaded again. It asks for confirmation before replacing the checkout. Use `--yes` to skip the prompt, `--keep-old` to keep a dated copy of the previous checkout, or `--check` to inspect the latest release without downloading or changing files.

The updater does not delete the old checkout if downloading, checksum verification, extraction, or `bin/install-termux.sh` fails. During in-place replacement it temporarily moves the old checkout aside and restores it if moving the new checkout fails.

## Data preservation

Full and Lite images remain under `VM_STATE_ROOT`. Lite `tiny`, `safe`, and `lts` use one shared image. Installed packages, `/root` files, persistent PATH entries, backups, and exports therefore survive project updates. The update changes project files, launchers, kernels, and documentation; it is not an automatic `apk upgrade` inside Alpine.

## Verification

The release was verified with shell syntax checks, Python compilation of the prior test helpers, launcher tests, ext4 write tests, persistent-storage tests, Full/Lite export/import tests, Full/Lite authentication boot matrix, real serial login sessions, sparse archive extraction, fresh-install workflow, same-directory update workflow, separate old/new checkout workflow, failed-installer preservation, and download-only no-side-effect behavior.

The local tests used a fake `pkg` command where required to avoid changing the sandbox host. Physical Android OTG permission, AR9271 power stability, and real Termux package installation still require execution on a target phone.

## Safety

The public installer and updater only use the published GitHub archive and its SHA-256 asset. They refuse unsafe extraction paths, reject symbolic-link project targets, keep VM state outside the project directory, and never run a destructive replacement before verification and installer success. Use the VM only on networks and devices you own or are explicitly authorized to assess.
