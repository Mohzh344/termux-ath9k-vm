# Alpine ARM64 Wi-Fi VM for Termux

A real Alpine Linux ARM64 virtual machine for Android/Termux, powered by QEMU. The guest kernel is built from Alpine `linux-lts` and includes the `ath9k_htc` driver, USB host/XHCI support, and the AR9271 firmware package. The project is designed for a rootless Android host: Android grants access to the USB device through Termux:API, while the Linux guest owns the driver and wireless interface.

> **Status:** The VM image and guest boot path were tested locally through Alpine OpenRC. Physical AR9271/OTG passthrough must still be tested on the target phone because this build environment cannot emulate Android USB permissions or a real adapter.

## Features

| Component | Included capability |
|---|---|
| Guest OS | Alpine Linux 3.24.1, ARM64 |
| Guest kernel | Alpine `linux-lts` `6.18.44-r0` |
| Wireless driver | `ath9k_htc.ko.gz` for Atheros AR9271-class adapters |
| Firmware | `htc_9271-1.4.0.fw.zst` and related ath9k_htc firmware |
| Virtual hardware | QEMU `virt`, virtio disk/network, XHCI USB controller |
| USB path | Direct `termux-usb -E`/QEMU `usb-host`; optional usb-redir fallback |
| Guest tools | `iw`, `lsusb`, `tcpdump`, `aircrack-ng`, `wifi-diagnose` |
| Android host | No Android root is required by the design |

## Download

The recommended installation method is to download the **Full + Lite Unified** archive from the [latest GitHub Release](https://github.com/Mohzh344/termux-ath9k-vm/releases/latest). It contains both ready-to-run VM bundles, their matching kernels and initramfs files, launch scripts, and documentation. The source repository itself intentionally does not store the 2 GiB sparse disk images in Git history; GitHub Release assets are used for large binaries.

After downloading `termux-ath9k-vm-v031-full-lite-ready.tar.gz` into Termux, verify the checksum:

```sh
sha256sum -c termux-ath9k-vm-v031-full-lite-ready.tar.gz.sha256
```

Extract it under the Termux home directory without stripping the archive root:

```sh
mkdir -p "$HOME/termux-ath9k-vm"
tar --sparse -xzf termux-ath9k-vm-v031-full-lite-ready.tar.gz -C "$HOME/termux-ath9k-vm" --strip-components=1
cd "$HOME/termux-ath9k-vm"
```

The extracted directory contains `full/` and `lite/`; the top-level `bin/vm-launcher.sh` selects between them.

## Requirements

Install Termux and Termux:API from compatible official sources. Do not mix Termux packages from incompatible distributors. The VM requires an ARM64 Android device, sufficient free storage, and the Termux packages below:

```sh
pkg update
pkg install -y qemu-system-aarch64-headless termux-api socat e2fsprogs
```

The recommended rootless-TCG profile assigns 768 MiB of RAM and one virtual CPU. On an Android phone without KVM, extra virtual CPUs can slow boot through TCG synchronization and 1536 MiB may force Android to swap. Use 1024 MiB only when a workload demonstrably needs it.

## Installation script

The unified package includes `bin/install-termux.sh`. Run it from the extracted project directory:

```sh
cd "$HOME/termux-ath9k-vm"
bash bin/install-termux.sh
```

The script installs QEMU, Termux:API, `socat`, and `e2fsprogs`, then makes the top-level and nested launchers executable. It does not require Android root. The guest images use local serial consoles; no SSH server is enabled by default.

## Recommended: unified interactive launcher

The recommended entry point is the additive unified launcher below. It detects complete Full and Lite bundles, asks which one to use when both are present, offers Lite `safe`/`tiny`/`lts` selection, detects Android-visible USB devices, requests Android USB permission when a device is selected, and opens the guest console automatically.

```sh
cd "$HOME/termux-ath9k-vm"
./bin/vm-launcher.sh
```

For scripted selection, use `VM_VARIANT=full` or `VM_VARIANT=lite`; for Lite, set `KERNEL_TIER=safe`, `tiny`, or `lts`. Use `--dry-run` to inspect detection without starting QEMU. The launcher never rebuilds or deletes an image automatically.

For a USB device, QEMU is intentionally launched by `termux-usb -E -e` so it inherits Android's granted USB file descriptor. The launcher then connects the guest serial console through a private Unix socket in the same Termux session; no second session and no manual `termux-usb -l` command are required.

Before its first boot of a selected image, the launcher performs an **offline** `securetty` verification. If `ttyAMA0` is missing, it adds it, stores a sparse backup alongside the image, and verifies the result before booting. If it is already present, it makes no image change. This permits root login on QEMU's serial console. The repair uses `debugfs`, supplied by `e2fsprogs`; if it is not installed, run `pkg install e2fsprogs` once. Never run this repair while the VM is running.

The established manual scripts remain available for advanced/debug use: `bin/launch-vm.sh`, `bin/launch-vm-rescue.sh`, and `bin/usb-attach-direct.sh`. Lite v0.3.1 additionally configures DHCP automatically when `ENABLE_NET=1`, restores apk file locking in both custom tiers, and validates the Lite ext4 image before packaging.

## Start the VM without USB

Start the guest and enter its serial console with:

```sh
cd "$HOME/termux-ath9k-vm"
./bin/launch-vm.sh
```

The release image opens a **root shell directly** on QEMU's local-only `ttyAMA0` serial console; there is intentionally no login or password prompt. This avoids the incompatible BusyBox shadow fallback path. Do not expose this VM console to an untrusted network or user. If you later install a remote login service, create a password first:

```sh
passwd
```

The guest uses a serial console and does not install a graphical desktop. This keeps CPU, RAM, battery, and storage use much lower than a graphical Linux VM. Stop the VM with `Ctrl-C` in the Termux session.

For a lower-resource phone:

```sh
RAM=768 SMP=1 ./bin/launch-vm.sh
```

For a balanced profile on a 6 GiB phone:

```sh
RAM=1024 SMP=1 ./bin/launch-vm.sh
```

## Attach an AR9271 USB adapter

Connect the adapter through USB OTG, then list Android-visible USB devices:

```sh
termux-usb -l
```

Find the AR9271 device path, normally similar to `/dev/bus/usb/001/003`, and run the direct launcher:

```sh
cd "$HOME/termux-ath9k-vm"
./bin/usb-attach-direct.sh /dev/bus/usb/001/003
```

Android may show a USB permission dialog. Accept it for the adapter. The launcher uses `termux-usb -E -e`, which exports the Android USB file descriptor as `TERMUX_USB_FD`. QEMU then uses its libusb backend and attaches the granted device as a USB host device. The launcher currently matches the AR9271 USB identifiers `0cf3:9271`.

Inside the guest, use the non-destructive diagnostic helper:

```sh
wifi-diagnose
```

The expected diagnostic sequence is: the adapter appears in `lsusb`; the `ath9k_htc` driver is built-in or registered; the firmware is found; and a wireless interface appears in `iw dev` or `ip link`. Seeing the device in `lsusb` alone does not prove that the driver loaded successfully.

## Optional usb-redir fallback

If direct QEMU `usb-host` attachment does not work with the installed Termux QEMU/libusb build, the project includes `bin/usb-attach-redir.sh`. It expects a Termux-aware `usbredirect` executable that accepts the file descriptor supplied by `termux-usb`:

```sh
cd "$HOME/termux-ath9k-vm"
USBREDIRECT="$HOME/.local/bin/usbredirect" \
  ./bin/usb-attach-redir.sh /dev/bus/usb/001/003
```

The fallback exposes the device over a localhost USB-redirection stream and connects QEMU to it with `usb-redir`. It is included for compatibility testing; direct mode should be tried first.

## Rebuild the image

Rebuilding is optional. It is normally easier to use the release image. To rebuild on a Linux workstation, WSL environment, or another ARM64-capable build host, download the pinned Alpine artifacts first:

```sh
cd "$HOME/termux-ath9k-vm"
./src/download-artifacts.sh
./src/build-image.sh
```

The build creates `guest/alpine-ath9k.img`, `guest/vmlinuz-lts`, and `guest/initramfs-lts`. It uses the full Alpine `linux-lts` package rather than the smaller `linux-virt` package because `linux-virt` does not contain the ath9k_htc wireless module. The build uses QEMU user-mode emulation and does not require the Android host to be rooted.

## Release notes

Detailed release history and the v0.3.0 migration/security notes are in [`docs/RELEASE-v0.3.0.md`](docs/RELEASE-v0.3.0.md).

## Verification

The following local checks were completed for the released image:

```text
Alpine Init 3.14.0-r0
Mounting root: ok.
OpenRC 0.63.2 is starting up Linux 6.18.44-0-lts (aarch64)
```

The ext4 image contains the matching module tree, `ath9k_htc.ko.gz`, AR9271 firmware, `iw`, `lsusb`, `aircrack-ng`, and `aireplay-ng` under Alpine's standard executable paths. The project also includes `docs/TEST-RESULTS.md` with the test boundary and the checks that must be repeated on the physical phone. Maintainers can create a sparse-aware release archive only after shutting down the VM with `src/package-release.sh vX.Y.Z`; it regenerates the guest checksum manifest inside the archive and refuses to package a running disk image.

## Resource and hardware notes

The image is terminal-only and is intentionally lighter than a desktop VM. The sparse disk is 2 GiB nominally and currently contains roughly a few hundred MiB of data; it can grow as packages are installed. The main runtime cost is the QEMU guest RAM allocation, not the kernel file size. An external AR9271 adapter may draw enough power to cause OTG resets on some phones. If the adapter repeatedly disconnects, test a short, high-quality OTG cable and a charge-through/Y-OTG arrangement with an appropriate 5 V source rather than changing the guest kernel first.

## Safety and legal use

Use monitor-mode or packet-transmission capabilities only on networks and devices that you own or are explicitly authorized to assess. This repository does not include automation for credential theft, client disruption, WPS attacks, or unauthorized access. Regulatory-domain and transmit-power limits must not be bypassed.

## Project layout

| Path | Purpose |
|---|---|
| `bin/vm-launcher.sh` | **Recommended** interactive entry point: resource choices, USB selection, automatic console, and clean shutdown |
| `bin/launch-vm.sh` | Low-level guest launcher without USB or with a selected USB mode |
| `bin/usb-attach-direct.sh` | Grants one Android USB device and starts direct QEMU passthrough |
| `bin/qemu-direct-inner.sh` | Receives `TERMUX_USB_FD` and starts QEMU |
| `bin/usb-attach-redir.sh` | Optional localhost usb-redir fallback |
| `src/install-termux.sh` | Installs host packages and verifies the release files |
| `src/download-artifacts.sh` | Downloads pinned Alpine build inputs |
| `src/build-image.sh` | Rebuilds the guest disk, kernel, and initramfs |
| `src/test-boot.sh` | Performs a local non-USB QEMU boot test |
| `src/package-release.sh` | Creates a sparse-aware, checksum-verified release archive from a stopped VM image |
| `src/repair-root-login.sh` | Offline repair for a stopped image whose initial BusyBox root login is broken |
| `src/enable-root-autologin.sh` | Offline emergency recovery: configure ttyAMA0 as a direct root shell without login/password |
| `docs/TEST-RESULTS.md` | Records verified behavior and physical-device test limits |

## References

1. [Termux:API `termux-usb` implementation](https://github.com/termux/termux-api-package/blob/master/scripts/termux-usb.in)
2. [Termux libusb `TERMUX_USB_FD` support](https://github.com/termux/termux-packages/blob/master/packages/libusb/termux-usb-support.patch)
3. [Termux/QEMU USB redirection report](https://github.com/termux/termux-packages/issues/19635)
4. [QEMU USB device documentation](https://qemu-project.gitlab.io/qemu/system/devices/usb.html)
5. [Alpine `linux-lts` ARM64 package](https://pkgs.alpinelinux.org/package/v3.24/main/aarch64/linux-lts)
6. [Alpine ath9k_htc firmware package](https://pkgs.alpinelinux.org/packages?name=linux-firmware-ath9k_htc&branch=v3.24&arch=aarch64)
