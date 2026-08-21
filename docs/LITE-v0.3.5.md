# Lite v0.3.5

Lite v0.3.5 keeps the compact Alpine ARM64 guest and adds persistent host-side storage for the guest image. The release tree contains kernels and launchers; the writable guest filesystem is adopted into the user's persistent data directory on the first installation.

## Persistent image behavior

The `tiny`, `safe`, and `lts` Lite choices use the same persistent image. Changing the kernel tier does not reinstall packages or remove files. The recommended launcher selects the image from:

```text
$VM_STATE_ROOT/lite/alpine-ath9k-v030-lite.img
```

The default `VM_STATE_ROOT` is `$XDG_DATA_HOME/android-wifi-monitor-injection-rootless` when `XDG_DATA_HOME` is set, otherwise `$HOME/.local/share/android-wifi-monitor-injection-rootless`.

## Migration

Export portable user data while the Lite VM is stopped:

```sh
./bin/vm-export.sh --lite
```

Import that export into a Full or Lite target while the target is stopped:

```sh
./bin/vm-import.sh --full /path/to/lite-user-data.tar.gz
```

The import restores `/root`, `/home`, `/opt`, `/usr/local`, `/etc/profile.d`, and the explicitly requested apk package list. It does not copy `/etc/shadow`, `/etc/passwd`, `/etc/inittab`, repositories, kernels, firmware, or kernel modules. After booting the target with Internet access, run the generated command:

```sh
/root/.vm-migration/apply-packages.sh
```

Package signatures remain enabled by apk. The command requires a compatible Alpine ARM64 repository and an Internet-enabled guest.

## Backup

Create a sparse-aware image backup before auth changes or migration:

```sh
./bin/vm-backup.sh --lite
```

The VM must be stopped before a backup or offline import. The importer creates a safety backup by default.

## Kernel tiers

`safe` is the recommended compatibility-oriented custom kernel. `tiny` is the smaller AR9271-focused build. `lts` is the fallback kernel plus initramfs. These are boot-kernel choices, not monitor-mode switches. USB passthrough and wireless operations remain inside the guest and require an authorized adapter and network.
