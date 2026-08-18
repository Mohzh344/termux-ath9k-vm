# v0.3.0 Trade-offs

## Scope

The v0.3.0 release is split into two images. `v0.3.0-lite` is the recommended image for phones running QEMU TCG without KVM. `v0.3.0` is the full runtime image with the commonly used Wi-Fi diagnostics and security packages already installed. Source-built capture and WPS tools are intentionally not part of the default Lite build; they can be installed later from the guest-side installer when explicitly requested.

| Change | Benefit | Risk or limitation | Reversible? | Recommendation |
|---|---|---|---|---|
| Tier A `vmlinuz-tiny` | Smallest kernel, built-in AR9271/ath9k_htc, cfg80211/mac80211, XHCI, virtio, ext4, serial; fewer TCG translations | Less insurance for unusual USB serial devices and future hardware | Yes; select `KERNEL_TIER=lts` or `safe` | Use for a dedicated AR9271 Wi-Fi VM |
| Tier B `vmlinuz-safe` | Tier A plus USB hub, CDC ACM, and common USB-serial drivers | Slightly larger image and more built-in code | Yes; select `KERNEL_TIER=tiny` or `lts` | Default for general external-USB use |
| Direct-root boot for tiny/safe | Avoids the Alpine initramfs module/switch-root path; removes about 9 MB initramfs from the active boot path and fixes custom-kernel OpenRC handoff | Custom kernels must keep root storage, ext4, serial, and USB drivers built in | Yes; `KERNEL_TIER=lts` uses the original initramfs path | Use with the custom tiers; keep lts as fallback |
| `rootflags=rw` | Ensures the guest root filesystem is writable from the first OpenRC stage | A writable root is less conservative than a read-only root | Yes; override `APPEND` manually if needed | Keep enabled for normal VM operation |
| Lite excludes aircrack-ng/hcxdumptool/WPS sources | Smaller disk footprint, faster image construction, less background package and compiler overhead | Tools are not available until installed inside the guest | Yes; run `/usr/local/sbin/install-wifi-tools` | Recommended on constrained phones |
| Full runtime packages | Includes aircrack-ng, tcpdump, hostapd, wireless-regdb, iw, usbutils, kmod, and wireless-tools | Larger image and more packages to update | Yes; use Lite instead | Use when the tools are needed immediately |
| Guest-side Wi-Fi installer | Allows optional installation after boot; does not launch capture, deauthentication, or WPS actions automatically | Source builds require network access, storage, and CPU time inside the guest | Yes; do not run it | Use only when required |
| WPS tools omitted from default build | Avoids heavy compilation and prevents accidental inclusion of attack automation | Reaver/Bully/Wifite are not preinstalled; upstream Bully has OpenSSL 3 compatibility issues | Yes; use a separate, explicitly reviewed build | Keep opt-in |
| Serial root autologin | Eliminates the v0.1.0 failure mode where an empty or unknown root password prevented access; verified with QEMU serial login | Anyone with access to the local VM console receives root; this must not be exposed over SSH or a shared network | Yes; build with `AUTOLOGIN=0 ROOT_PASSWORD_HASH=<crypt-hash>` | Recommended for a local-only Termux VM |
| No SSH server by default in Lite | Removes a remote attack surface and package overhead | Remote administration is unavailable until explicitly installed/configured | Yes; install OpenSSH in the guest | Keep disabled for the Wi-Fi-only use case |
| `wifi-only` profile: 512 MB/1 CPU/no 9p/no network | Minimizes TCG scheduling, device emulation, and memory overhead | Not suitable for compiling large packages or running several tools concurrently | Yes; override `RAM`, `SMP`, `ENABLE_NET`, or `SHARE_MODE` | Recommended first profile |
| `balanced` profile: 768 MB/2 CPU | More usable for package installation and simultaneous diagnostics | More TCG work than wifi-only | Yes | Use for interactive tooling |
| `default` profile: 1024 MB/2 CPU | Conservative general-purpose fallback | Not as light as wifi-only | Yes | Use when the workload is uncertain |
| `legacy` profile: 1536 MB/4 CPU/9p | Preserves the v0.1.0-style resource envelope and share | Highest overhead and 9p latency | Yes | Fallback only |
| `thread=multi` | Usually improves CPU throughput on hosts with multiple host cores | May add scheduling variability on low-end phones | Yes; set `ACCEL=tcg,thread=single` | Benchmark both; default multi |
| CPU `max` | Broadest emulated ARM feature set and usually best TCG throughput | CPU feature behavior can vary across QEMU builds | Yes; set `CPU_MODEL=cortex-a72` or `cortex-a76` | Benchmark against the phone's stable option |
| USB direct passthrough | Shorter path and normally lower latency than usb-redir | Depends on Termux USB FD lifecycle and Android OTG stability | Yes; set `USB_MODE=redir` | Prefer direct for AR9271 |
| USB redirection | Fallback when direct FD passthrough is unavailable | Adds a TCP/redirector path and latency | Yes; set `USB_MODE=direct` | Use for reliability troubleshooting |

## Capability invariants

The following capabilities are not removed from the custom tiers: `CFG80211`, `MAC80211`, `ATH_COMMON`, `ATH9K_HW`, `ATH9K_COMMON`, `ATH9K_HTC`, `USB_XHCI_HCD`, `VIRTIO_BLK`, `EXT4_FS`, `PACKET`, `FW_LOADER`, and `FW_LOADER_COMPRESS_ZSTD`. The AR9271 firmware remains in the Alpine filesystem under the standard firmware path.

> The Lite image is deliberately a smaller **VM runtime**, not a replacement for the Wi-Fi tools. It keeps the kernel, firmware, USB path, serial console, `iw`, `lsusb`, and diagnostics available, while moving optional package installation to the guest.

## Reversibility

The launcher keeps `vmlinuz-lts` beside `vmlinuz-tiny` and `vmlinuz-safe`. Select the fallback with `IMAGE_VARIANT=legacy KERNEL_TIER=lts` or select the full initramfs-backed Alpine kernel with `KERNEL_TIER=lts`. The Lite and Full disks are separate files, so changing the active image does not overwrite the other image.
