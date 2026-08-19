#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$PROJECT_DIR/artifacts"
GUEST="$PROJECT_DIR/guest"
ROOTFS="$GUEST/rootfs-lite"
DISK="${1:-$GUEST/alpine-ath9k-v030-lite.img}"
DISK_SIZE="${DISK_SIZE:-2G}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.24}"

need() { command -v "$1" >/dev/null || { echo "missing command: $1" >&2; exit 1; }; }
for x in tar truncate mke2fs e2fsck qemu-aarch64-static proot; do need "$x"; done
for f in alpine-minirootfs-3.24.1-aarch64.tar.gz linux-lts-6.18.44-r0.apk linux-firmware-ath9k_htc-20260519-r0.apk scanelf-1.3.9-r1.apk; do
  [ -s "$ARTIFACTS/$f" ] || { echo "missing artifact: $ARTIFACTS/$f" >&2; exit 1; }
done

mkdir -p "$GUEST" "$GUEST/boot"
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"

echo '[1/7] Extracting Alpine minirootfs for Lite'
tar -xzf "$ARTIFACTS/alpine-minirootfs-3.24.1-aarch64.tar.gz" -C "$ROOTFS"

echo '[2/7] Adding the canonical linux-lts package and AR9271 firmware'
tar --warning=no-unknown-keyword -xzf "$ARTIFACTS/linux-lts-6.18.44-r0.apk" -C "$ROOTFS"
tar --warning=no-unknown-keyword -xzf "$ARTIFACTS/linux-firmware-ath9k_htc-20260519-r0.apk" -C "$ROOTFS"
install -m 0755 "$(command -v qemu-aarch64-static)" "$ROOTFS/usr/bin/qemu-aarch64-static"

cat > "$ROOTFS/etc/apk/repositories" <<EOF
$ALPINE_MIRROR/main
$ALPINE_MIRROR/community
EOF
[ -f /etc/resolv.conf ] && cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
mkdir -p "$ROOTFS/usr/local/sbin" "$ROOTFS/etc/profile.d" "$ROOTFS/var/lib/termux-ath9k-vm"

printf '%s\n' ath9k-vm > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
cat > "$ROOTFS/etc/fstab" <<'EOF'
/dev/vda / ext4 defaults,noatime 0 1
proc /proc proc nosuid,noexec,nodev 0 0
sysfs /sys sysfs nosuid,noexec,nodev 0 0
devpts /dev/pts devpts gid=5,mode=620,ptmxmode=666 0 0
EOF
cat > "$ROOTFS/etc/motd" <<'EOF'
Alpine ARM64 WiFi VM — Lite

This is the lightweight v0.3.3 companion image. The console starts as a direct root login shell for profile loading; USB devices are attached by the Android/Termux launcher.
Run /usr/local/sbin/wifi-diagnose for non-destructive diagnostics.
Run /usr/local/sbin/install-wifi-tools only when optional Wi-Fi packages are needed.
EOF

cat > "$ROOTFS/usr/local/sbin/wifi-diagnose" <<'EOF'
#!/bin/sh
set -u
printf '%s\n' '=== kernel ==='; uname -a
printf '%s\n' '=== USB ==='; command -v lsusb >/dev/null 2>&1 && lsusb || echo 'lsusb unavailable'
printf '%s\n' '=== ath9k_htc driver ==='; if [ -d /sys/module/ath9k_htc ]; then echo 'ath9k_htc: built-in or registered'; elif command -v modinfo >/dev/null 2>&1 && modinfo ath9k_htc 2>&1; then :; else echo 'ath9k_htc: not visible'; fi
printf '%s\n' '=== interfaces ==='; command -v iw >/dev/null 2>&1 && iw dev 2>&1 || ip link 2>&1 || true
printf '%s\n' '=== regulatory state ==='; command -v iw >/dev/null 2>&1 && iw reg get 2>&1 || true
printf '%s\n' '=== recent kernel log ==='; dmesg | tail -n 80 2>&1 || true
EOF
chmod 0755 "$ROOTFS/usr/local/sbin/wifi-diagnose"
cat > "$ROOTFS/usr/local/sbin/qemu-net-init" <<'EOF'
#!/bin/sh
# QEMU user networking exposes a virtio NIC but does not run DHCP for the guest.
# Configure it only when eth0 exists; wifi-only mode has no NIC and remains offline.
set -u
command -v ip >/dev/null 2>&1 || exit 0
ip link show eth0 >/dev/null 2>&1 || exit 0
ip link set eth0 up 2>/dev/null || exit 0
if ! ip -4 addr show dev eth0 2>/dev/null | grep -q 'inet '; then
  if command -v udhcpc >/dev/null 2>&1; then
    udhcpc -i eth0 -n -q -t 5 -T 3 >/dev/null 2>&1 || true
  fi
fi
# QEMU user-mode networking provides its DNS proxy at 10.0.2.3.
if ip -4 addr show dev eth0 2>/dev/null | grep -q 'inet '; then
  printf '%s\n' 'nameserver 10.0.2.3' > /etc/resolv.conf
fi
exit 0
EOF
chmod 0755 "$ROOTFS/usr/local/sbin/qemu-net-init"
install -m 0755 "$PROJECT_DIR/src/guest-install-wifi-tools.sh" "$ROOTFS/usr/local/sbin/install-wifi-tools"
ln -sf /usr/local/sbin/install-wifi-tools "$ROOTFS/usr/bin/install-wifi-tools"
ln -sf /usr/local/sbin/wifi-diagnose "$ROOTFS/usr/bin/wifi-diagnose"
printf '%s\n' 'export LANG=C' 'export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' "alias ll='ls -alF'" > "$ROOTFS/etc/profile.d/wifi-vm.sh"
printf '%s\n' 'variant=lite' 'release=v0.3.3' 'full_reference=v0.3.0-unchanged' 'optional_tools=guest-installer' > "$ROOTFS/etc/termux-ath9k-vm-image"

# Lite keeps the console, firmware, iw, lsusb, and diagnostics. It does not
# install aircrack-ng, tcpdump, hostapd, OpenSSH, Python, or compiler packages.
qemu-aarch64-static -L "$ROOTFS" "$ROOTFS/sbin/apk" --root "$ROOTFS" --arch aarch64 update
qemu-aarch64-static -L "$ROOTFS" "$ROOTFS/sbin/apk" --root "$ROOTFS" --arch aarch64 --no-cache --no-scripts add \
  alpine-base bash ca-certificates wireless-regdb iproute2 iw usbutils kmod ethtool wireless-tools busybox-extras \
  mkinitfs pax-utils scanelf which cpio gzip
if [ -s "$ARTIFACTS/scanelf-1.3.9-r1.apk" ]; then
  tar --warning=no-unknown-keyword -xzf "$ARTIFACTS/scanelf-1.3.9-r1.apk" -C "$ROOTFS"
fi
sed -i 's/which scanelf/command -v scanelf/; s/which objdump/command -v objdump/; s/which readelf/command -v readelf/' "$ROOTFS/usr/bin/lddtree"
# --no-scripts provisioning skips package triggers, so regenerate the CA bundle
# inside the ARM64 rootfs before packaging. Keep HTTPS as the default repository URL.
if [ -x "$ROOTFS/usr/sbin/update-ca-certificates" ]; then
  proot -0 -r "$ROOTFS" -w / -q /usr/bin/qemu-aarch64-static /usr/sbin/update-ca-certificates --fresh >/dev/null
fi
mkdir -p "$ROOTFS/etc/ssl" "$ROOTFS/etc/apk"
ln -sfn /etc/ssl/certs/ca-certificates.crt "$ROOTFS/etc/ssl/cert.pem"
# libapk uses ca.pem for the server trust bundle; cert.pem/cert.key are
# reserved for optional client-certificate authentication and must not be
# symlinked to the CA bundle.
rm -f "$ROOTFS/etc/apk/cert.pem" "$ROOTFS/etc/apk/cert.key"
ln -sfn /etc/ssl/certs/ca-certificates.crt "$ROOTFS/etc/apk/ca.pem"

# Keep the same initramfs generation path as the user's Full v0.3.0 builder.
cp -f "$ROOTFS/boot/vmlinuz-lts" "$GUEST/vmlinuz-lts-lite"
mkdir -p "$GUEST/build-output"
proot -0 -r "$ROOTFS" -w / -b "$GUEST/build-output:/build" \
  -q /usr/bin/qemu-aarch64-static /sbin/mkinitfs -F 'base virtio ext4 usb' \
  -o /build/initramfs-lts-lite 6.18.44-0-lts
cp -f "$GUEST/build-output/initramfs-lts-lite" "$GUEST/initramfs-lts-lite"
rm -rf "$GUEST/build-output"
rm -f "$ROOTFS/usr/bin/qemu-aarch64-static"

# Start a private local serial root login shell, not a login manager or password
# prompt. The `-l` flag makes BusyBox ash read /etc/profile automatically.
cat > "$ROOTFS/etc/inittab" <<'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::sysinit:/usr/local/sbin/qemu-net-init
::wait:/sbin/openrc default
ttyAMA0::respawn:/bin/sh -l
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF
sed -i 's/^root:[^:]*:/root::/' "$ROOTFS/etc/passwd"
sed -i 's/^root:[^:]*:/root::/' "$ROOTFS/etc/shadow"
# Keep a standard nine-field shadow record so BusyBox passwd updates the
# shadow database and login validates the resulting hash.
awk -F: -v OFS=: '$1 == "root" { print $1,$2,($3==""?"0":$3),($4==""?"0":$4),($5==""?"99999":$5),($6==""?"7":$6),$7,$8,$9; next } { print }' "$ROOTFS/etc/shadow" > "$ROOTFS/etc/shadow.normalized"
mv "$ROOTFS/etc/shadow.normalized" "$ROOTFS/etc/shadow"
grep -qxF ttyAMA0 "$ROOTFS/etc/securetty" || printf '%s\n' ttyAMA0 >> "$ROOTFS/etc/securetty"
chmod 0600 "$ROOTFS/etc/shadow"
rm -f "$ROOTFS/etc/ssh/sshd_config" 2>/dev/null || true

find "$ROOTFS" -type d -exec chmod u+rx {} +
find "$ROOTFS" -type f ! -readable -exec chmod u+r {} +
rm -f "$DISK"
truncate -s "$DISK_SIZE" "$DISK"
mke2fs -q -F -t ext4 -L ath9k-vm-lite -d "$ROOTFS" "$DISK"
# Reject a dirty or inconsistent image before it can enter a release archive.
e2fsck -fn "$DISK" >/dev/null
if [ "${KEEP_ROOTFS:-0}" != 1 ]; then rm -rf "$ROOTFS"; fi
sha256sum "$DISK" "$GUEST/vmlinuz-lts-lite" "$GUEST/initramfs-lts-lite" > "$GUEST/SHA256SUMS-lite"
printf '%s\n' "[7/7] Built Lite image: $DISK"
ls -lh "$DISK" "$GUEST/vmlinuz-lts-lite" "$GUEST/initramfs-lts-lite" "$GUEST/SHA256SUMS-lite"
