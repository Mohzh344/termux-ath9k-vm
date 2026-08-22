# Lite v0.3.6

Lite v0.3.6 keeps the compact Alpine ARM64 guest and the persistent-image model introduced in v0.3.5. The release tree contains kernels and launchers; the writable guest filesystem is adopted into the user's persistent data directory on first installation.

## Persistent image behavior

The `tiny`, `safe`, and `lts` Lite choices use the same persistent image. Changing the kernel tier does not reinstall packages or remove files. The image is normally stored at:

```text
$VM_STATE_ROOT/lite/alpine-ath9k-v030-lite.img
```

The default `VM_STATE_ROOT` is `$XDG_DATA_HOME/android-wifi-monitor-injection-rootless` when `XDG_DATA_HOME` is set, otherwise `$HOME/.local/share/android-wifi-monitor-injection-rootless`.

## Unified administration

Use the single host-side administration command for diagnostics and maintenance:

```sh
./bin/vmctl.sh doctor --lite
./bin/vmctl.sh info --lite
./bin/vmctl.sh status
./bin/vmctl.sh backup --lite
```

Operations that write the image require the VM to be stopped. An atomic image lock prevents backup, import, resize, and PATH changes from running concurrently on the same image. The lock is recovered if a previous Termux process was interrupted.

## Persistent PATH and image size

Add a tool directory permanently without editing the guest manually:

```sh
./bin/vmctl.sh path add --lite /opt/my-tool/bin
./bin/vmctl.sh path list --lite
```

The managed file is `/etc/profile.d/vmctl-path.sh`, so the entry is available after reboot and in both direct root-console and normal login modes.

Grow a stopped Lite image when more space is needed:

```sh
./bin/vmctl.sh resize --lite 3G
```

The command creates a safety backup, checks ext4, grows the sparse file, and validates the result.

## Migration

Export portable user data while the Lite VM is stopped:

```sh
./bin/vmctl.sh export --lite
```

Import that export into a Full or Lite target while the target is stopped:

```sh
./bin/vmctl.sh import --full /path/to/lite-user-data.tar.gz
```

The import restores `/root`, `/home`, `/opt`, `/usr/local`, `/etc/profile.d`, and the explicitly requested apk package list. It does not copy `/etc/shadow`, `/etc/passwd`, `/etc/inittab`, repositories, kernels, firmware, or kernel modules. After booting the target with Internet access, run the generated command:

```sh
/root/.vm-migration/apply-packages.sh
```

Package signatures remain enabled by apk. The command requires a compatible Alpine ARM64 repository and an Internet-enabled guest.

## USB diagnostics

Before launching with an adapter, run:

```sh
./bin/vmctl.sh usb
./bin/vmctl.sh doctor --lite
```

These commands inspect Android-visible USB devices and the AR9271 signature when Termux:API is available. They do not grant permission or start QEMU; the launcher performs the permission request.

## Kernel tiers

`safe` is the recommended compatibility-oriented custom kernel. `tiny` is the smaller AR9271-focused build. `lts` is the fallback kernel plus initramfs. These are boot-kernel choices, not monitor-mode switches. USB passthrough and wireless operations remain inside the guest and require an authorized adapter and network.
