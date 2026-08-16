# Test Results

## Verified in the build environment

The project builds an Alpine Linux 3.24.1 ARM64 ext4 guest image with a nominal size of 2 GiB. The image uses Alpine `linux-lts-6.18.44-r0`, and the matching module tree is `6.18.44-0-lts`. The image contains `ath9k_htc.ko.gz` and the AR9271 firmware files `htc_9271-1.4.0.fw.zst` and `htc_7010-1.4.0.fw.zst`.

The `initramfs-lts` is generated from the same module tree with the explicit features `base virtio ext4 usb`. It contains the `virtio_blk`, `xhci-hcd`, and `ext4` modules, BusyBox, and the Alpine `/init` script.

A local QEMU boot reached Alpine OpenRC without a kernel panic:

```text
Alpine Init 3.14.0-r0
Mounting root: ok.
OpenRC 0.63.2 is starting up Linux 6.18.44-0-lts (aarch64)
Welcome to Alpine Linux 3.24
Kernel 6.18.44-0-lts on aarch64 (/dev/ttyAMA0)
(none) login:
```

The image configures `getty` on `ttyAMA0`. The initial local root password is empty so the first console login can be completed by entering `root` and pressing Enter; the password should be changed immediately with `passwd`.

The image was also checked for `iw`, `lsusb`, `aircrack-ng`, and `aireplay-ng`. Alpine places the aircrack-ng executables under `/usr/sbin`.

## What cannot be tested in this environment

The build environment does not contain a physical Android phone, USB OTG port, or AR9271 adapter. Therefore, it does not claim to have tested USB identifier `0cf3:9271`, Android USB permission handling, or driver loading on a real device. The physical-phone test path is `termux-usb -E -e` followed by QEMU `usb-host`. If direct attachment fails, the optional `usb-redir` fallback can be compared.

A successful local boot proves the guest image layout, kernel/initramfs compatibility, virtio disk support, and guest XHCI initialization. It does not prove OTG stability, wireless performance, monitor-mode behavior, or packet transmission on every phone. Those depend on the Android version, Termux/QEMU build, USB adapter, cable, and available power.

## Non-destructive post-install checks

After the guest shell is available, run:

```sh
wifi-diagnose
modinfo ath9k_htc
lsusb
ip link
iw dev
```

The expected sequence is that the USB device appears, the module can be found, the firmware is available, and a wireless interface appears. Do not perform transmission tests on networks or devices without explicit authorization.
