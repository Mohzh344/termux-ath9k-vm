# v0.3.1 — Unified Full + Corrected Lite

## Release summary

`v0.3.1` is a corrective release for the combined Full + Lite distribution. It keeps the published **Full v0.3.0** bundle unchanged and ships a rebuilt **Lite v0.3.1** bundle in the same downloadable archive.

The main fixes address post-boot package installation, guest networking, HTTPS repository access, custom-kernel file locking, Lite image filesystem validation, and Lite build reproducibility.

## Corrective changes

### Custom kernel tiers

The Tier A `tiny` and Tier B `safe` kernels now include `CONFIG_FILE_LOCKING=y`. This restores the file-locking syscall required by Alpine `apk` while preserving the direct-root boot path and the built-in `ath9k_htc` driver. They also embed the signed `regulatory.db` and `regulatory.db.p7s` pair, allowing cfg80211 to load the regulatory database before the direct-root filesystem is mounted. The extra kernel footprint is small and is required for a usable package manager and early regulatory setup.

### Guest networking

Lite remains offline when using the default `wifi-only` profile. When `ENABLE_NET=1` supplies a virtio network device, the guest init path now brings up `eth0`, requests a DHCP lease, and writes the QEMU user-network DNS proxy (`10.0.2.3`) to `/etc/resolv.conf`. The Wi-Fi installer also checks for a usable IPv4 lease and produces an actionable message instead of passing a guaranteed-to-fail request to `apk`.

### HTTPS and apk

The image now regenerates its CA bundle after `apk --no-scripts` provisioning and installs the CA bundle at the path used by libapk (`/etc/apk/ca.pem`). The installer tries certificate validation first. In environments where the guest reports a certificate-verification failure, it can retry with `--check-certificate=no` while keeping Alpine APK package-signature verification enabled. Set `APK_ALLOW_INSECURE_FALLBACK=0` to require strict TLS certificate validation and fail instead of using that fallback.

The fallback is intended for constrained QEMU/Termux network paths and is explicitly reported to the user. It is not a substitute for validating the network or for testing untrusted repositories.

### Lite image and build

The Lite build no longer installs the unnecessary `binutils` package during image provisioning, avoiding the observed aarch64 extraction I/O failure in the acceptance environment. It now rejects an inconsistent image with a non-destructive `e2fsck -fn` check before packaging. Its `proot` build steps use `/` as their working directory to avoid the previous `can't chdir` warning.

### Documentation and optional tools

The installer status file now records that `wifite`, `bully`, `reaver`, `kismet`, `hcxdumptool`, and `hcxtools` are not supplied by the selected Alpine v3.24 repositories. The embedded regulatory database does not override an adapter EEPROM restriction or authorize use outside applicable local rules. The base installer still installs only the explicitly requested runtime set and does not start capture, deauthentication, WPS, injection, or other active wireless operations automatically.

## Compatibility and preserved behavior

The Full bundle remains the exact Full v0.3.0 release content. The unified launcher, Full launcher, USB wrappers, disk naming, direct USB paths, console behavior, and Full fallback path remain compatible with the previous combined archive. Lite's default `wifi-only` profile still does not add a network device unless networking is explicitly enabled.

## Verification performed

The corrective build completed in an isolated workspace. The resulting Lite filesystem passed `e2fsck -fn`. PTY boot tests reached a root console and clean poweroff for `tiny`, `safe`, and `lts`. Normal installer tests returned `INSTALL_RC:0` for all three Lite tiers, installed the base Wi-Fi runtime tools, and reported the unavailable optional packages without launching any wireless action. Unified launcher and Full regression tests were rerun separately; physical USB/OTG and AR9271 hardware testing remains a device-side step because no Android USB device is available in the build environment.

## Download and integrity

Download the combined archive and its checksum from the GitHub Release page. Verify the checksum before extraction:

```sh
sha256sum -c termux-ath9k-vm-v031-full-lite-ready.tar.gz.sha256
```

The archive contains one Full bundle and one Lite bundle. Use `bin/vm-launcher.sh` as the normal entry point and choose the variant and Lite tier interactively, or set `VM_VARIANT`, `KERNEL_TIER`, `PROFILE`, and related variables explicitly.
