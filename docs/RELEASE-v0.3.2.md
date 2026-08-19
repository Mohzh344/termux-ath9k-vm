# v0.3.2 — Android Clock Sync and Optional Internet

## Release summary

`v0.3.2` is an additive correction to the unified Full + Lite distribution. It keeps the nested **Full v0.3.0** bundle byte-for-byte unchanged and adds launch-policy improvements in the top-level unified layer and the Lite runtime path.

## Changes

### Android time synchronization

At every launch, the unified dispatcher reads the Android/Termux host clock with `date -u` and passes it to QEMU as `-rtc base=YYYY-MM-DDTHH:MM:SS`. It then waits for the local root console and executes `date -u -s` inside Alpine before handing the console to the user. This guest-side step is the authoritative synchronization because the minimal ARM64 kernels do not expose a usable `/dev/rtc` device to userspace. Both Lite and the unified Full adapter therefore start Alpine with the Android date and time without requiring network access or NTP.

`RTC_BASE` remains overrideable for development and deterministic tests. The adapter uses the same synchronization path for normal serial launches and USB passthrough launches.

### Interactive Internet choice

After the variant, Lite tier/profile, and USB choices, the launcher asks:

```text
Grant Internet access to this VM? [y/N]:
```

Answer `y` to attach QEMU user networking. Answer `n`, or press Enter, to keep the guest offline. In non-interactive mode, Full preserves its historical online behavior while Lite remains offline unless `ENABLE_NET=1` is explicitly supplied.

When enabled, Lite brings up its virtio interface with DHCP and configures the QEMU DNS proxy. When disabled, no virtio network device is attached. The choice is passed consistently through normal and USB passthrough launch paths.

### Full preservation boundary

The archive still contains the original published Full v0.3.0 files unchanged. The new `bin/launch-vm-full-unified.sh` adapter is outside the nested `full/` directory and is used only by the top-level unified launcher to add the optional Internet policy and RTC seed. The original Full low-level files remain available for advanced/manual use.

## Usage

```sh
sha256sum -c termux-ath9k-vm-v032-full-lite-ready.tar.gz.sha256
tar -xzf termux-ath9k-vm-v032-full-lite-ready.tar.gz
cd termux-ath9k-vm-full-lite
bash bin/install-termux.sh
bash bin/vm-launcher.sh
```

For scripted launches:

```sh
# Full with Internet, preserving the historical Full default.
VM_VARIANT=full ENABLE_NET=1 bash bin/vm-launcher.sh --non-interactive

# Lite without Internet.
VM_VARIANT=lite KERNEL_TIER=safe PROFILE=wifi-only ENABLE_NET=0 \
bash bin/vm-launcher.sh --non-interactive

# Lite with Internet for package installation.
VM_VARIANT=lite KERNEL_TIER=safe PROFILE=balanced ENABLE_NET=1 \
bash bin/vm-launcher.sh --non-interactive
```

The release does not start capture, deauthentication, WPS, injection, or other active wireless operations automatically. Use wireless functionality only on devices and networks for which you have authorization.
