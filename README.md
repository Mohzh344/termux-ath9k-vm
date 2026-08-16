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

The easiest installation method is to download the archive from the [latest GitHub Release](https://github.com/Mohzh344/termux-ath9k-vm/releases/latest). The archive contains the ready-to-run disk image, matching kernel and initramfs, launch scripts, and documentation. The source repository itself intentionally does not store the 2 GiB sparse disk image in Git history; GitHub Release assets are used for large binaries.

After downloading `termux-ath9k-vm-ready.tar.gz` into Termux, verify the checksum if the matching `.sha256` file is available:

```sh
sha256sum -c termux-ath9k-vm-ready.tar.gz.sha256
```

Extract it under the Termux home directory:

```sh
mkdir -p "$HOME/termux-ath9k-vm"
tar --sparse -xzf termux-ath9k-vm-ready.tar.gz \
  --strip-components=1 -C "$HOME/termux-ath9k-vm"
cd "$HOME/termux-ath9k-vm"
```

## Requirements

Install Termux and Termux:API from compatible official sources. Do not mix Termux packages from incompatible distributors. The VM requires an ARM64 Android device, sufficient free storage, and the Termux packages below:

```sh
pkg update
pkg install -y qemu-system-aarch64-headless termux-api
```

The default VM configuration assigns 1536 MiB of RAM and four virtual CPUs. A phone with 6–8 GiB RAM is recommended. For a 4 GiB device, start with the reduced profile shown below.

## Installation script

The package includes `src/install-termux.sh`. Run it from the extracted project directory:

```sh
cd "$HOME/termux-ath9k-vm"
chmod 700 src/install-termux.sh bin/*.sh
./src/install-termux.sh
```

The script installs QEMU and Termux:API, makes the launchers executable, checks the required image files, and verifies `guest/SHA256SUMS` when present. It does not require Android root.

## Start the VM without USB

Start the guest and enter its serial console with:

```sh
cd "$HOME/termux-ath9k-vm"
./bin/launch-vm.sh
```

The guest uses a serial console and does not install a graphical desktop. This keeps CPU, RAM, battery, and storage use much lower than a graphical Linux VM. Stop the VM with `Ctrl-C` in the Termux session.

For a lower-resource phone:

```sh
RAM=768 SMP=2 ./bin/launch-vm.sh
```

For a balanced profile on a 6 GiB phone:

```sh
RAM=1024 SMP=2 ./bin/launch-vm.sh
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

The expected diagnostic sequence is: the adapter appears in `lsusb`; the `ath9k_htc` module is available; the firmware is found; and a wireless interface appears in `iw dev` or `ip link`. Seeing the device in `lsusb` alone does not prove that the driver loaded successfully.

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

## Verification

The following local checks were completed for the released image:

```text
Alpine Init 3.14.0-r0
Mounting root: ok.
OpenRC 0.63.2 is starting up Linux 6.18.44-0-lts (aarch64)
```

The ext4 image contains the matching module tree, `ath9k_htc.ko.gz`, AR9271 firmware, `iw`, `lsusb`, `aircrack-ng`, and `aireplay-ng` under Alpine's standard executable paths. The project also includes `docs/TEST-RESULTS.md` with the test boundary and the checks that must be repeated on the physical phone.

## Resource and hardware notes

The image is terminal-only and is intentionally lighter than a desktop VM. The sparse disk is 2 GiB nominally and currently contains roughly a few hundred MiB of data; it can grow as packages are installed. The main runtime cost is the QEMU guest RAM allocation, not the kernel file size. An external AR9271 adapter may draw enough power to cause OTG resets on some phones. If the adapter repeatedly disconnects, test a short, high-quality OTG cable and a charge-through/Y-OTG arrangement with an appropriate 5 V source rather than changing the guest kernel first.

## Safety and legal use

Use monitor-mode or packet-transmission capabilities only on networks and devices that you own or are explicitly authorized to assess. This repository does not include automation for credential theft, client disruption, WPS attacks, or unauthorized access. Regulatory-domain and transmit-power limits must not be bypassed.

## Project layout

| Path | Purpose |
|---|---|
| `bin/launch-vm.sh` | Starts the guest without USB or with a selected USB mode |
| `bin/usb-attach-direct.sh` | Grants one Android USB device and starts direct QEMU passthrough |
| `bin/qemu-direct-inner.sh` | Receives `TERMUX_USB_FD` and starts QEMU |
| `bin/usb-attach-redir.sh` | Optional localhost usb-redir fallback |
| `src/install-termux.sh` | Installs host packages and verifies the release files |
| `src/download-artifacts.sh` | Downloads pinned Alpine build inputs |
| `src/build-image.sh` | Rebuilds the guest disk, kernel, and initramfs |
| `src/test-boot.sh` | Performs a local non-USB QEMU boot test |
| `docs/TEST-RESULTS.md` | Records verified behavior and physical-device test limits |

## References

1. [Termux:API `termux-usb` implementation](https://github.com/termux/termux-api-package/blob/master/scripts/termux-usb.in)
2. [Termux libusb `TERMUX_USB_FD` support](https://github.com/termux/termux-packages/blob/master/packages/libusb/termux-usb-support.patch)
3. [Termux/QEMU USB redirection report](https://github.com/termux/termux-packages/issues/19635)
4. [QEMU USB device documentation](https://qemu-project.gitlab.io/qemu/system/devices/usb.html)
5. [Alpine `linux-lts` ARM64 package](https://pkgs.alpinelinux.org/package/v3.24/main/aarch64/linux-lts)
6. [Alpine ath9k_htc firmware package](https://pkgs.alpinelinux.org/packages?name=linux-firmware-ath9k_htc&branch=v3.24&arch=aarch64)
