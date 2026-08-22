# Lite v0.3.7

Lite v0.3.7 keeps the compact Alpine ARM64 guest and persistent image model. The new project checkout defaults to `$HOME/awvm`, while persistent VM data defaults to `$HOME/.local/share/awvm`. Existing v0.3.5/v0.3.6 data under the previous long directory is reused automatically when present.

## New installation

From Termux, install the small bootstrap prerequisites and run the general installer:

```sh
pkg update -y
pkg install -y bash curl tar coreutils
curl -fL https://raw.githubusercontent.com/Mohzh344/android-wifi-monitor-injection-rootless/main/install.sh -o install.sh
bash install.sh
```

The installer creates `awvm`, downloads and verifies the full release archive, and adopts the Lite image into persistent storage.

## Updating an existing Lite VM

Run the bundled updater from the existing project:

```sh
cd "$HOME/awvm"
bash bin/awvm-update.sh
```

It downloads the thin update archive without downloading the large writable Lite image again. It preserves installed packages, `/root`, persistent PATH entries, and the shared image used by `tiny`, `safe`, and `lts`.

## Administration

```sh
./bin/vmctl.sh doctor --lite
./bin/vmctl.sh info --lite
./bin/vmctl.sh status
./bin/vmctl.sh backup --lite
./bin/vmctl.sh resize --lite 3G
./bin/vmctl.sh path add --lite /opt/my-tool/bin
./bin/vmctl.sh usb
```

The VM must be stopped for operations that write the image. The image-operation lock prevents concurrent management operations.

## Kernel tiers

`safe` is the recommended compatibility-oriented custom kernel. `tiny` is the smaller AR9271-focused build. `lts` is the fallback kernel plus initramfs. These choices use one Lite image; switching tiers does not reinstall packages or remove user files.
