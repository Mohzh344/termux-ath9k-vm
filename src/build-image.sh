#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$PROJECT_DIR/artifacts"
GUEST="$PROJECT_DIR/guest"
ROOTFS="$GUEST/rootfs"
DISK="${1:-$GUEST/alpine-ath9k.img}"
DISK_SIZE="${DISK_SIZE:-2G}"
ALPINE_MIRROR="${ALPINE_MIRROR:-http://dl-cdn.alpinelinux.org/alpine/v3.24}"

need() { command -v "$1" >/dev/null || { echo "missing command: $1" >&2; exit 1; }; }
for x in tar truncate mke2fs qemu-aarch64-static proot; do need "$x"; done

mkdir -p "$GUEST" "$GUEST/boot"
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"

echo "[1/7] Extracting Alpine minirootfs"
tar -xzf "$ARTIFACTS/alpine-minirootfs-3.24.1-aarch64.tar.gz" -C "$ROOTFS"

echo "[2/7] Installing matching linux-lts guest kernel and ath9k_htc firmware packages"
# APK files are tar archives. Extracting them into the guest makes the image self-contained.
tar --warning=no-unknown-keyword -xzf "$ARTIFACTS/linux-lts-6.18.44-r0.apk" -C "$ROOTFS"
tar --warning=no-unknown-keyword -xzf "$ARTIFACTS/linux-firmware-ath9k_htc-20260519-r0.apk" -C "$ROOTFS"
# The QEMU helper is needed only while running ARM64 apk scripts from this x86_64 builder.
install -m 0755 "$(command -v qemu-aarch64-static)" "$ROOTFS/usr/bin/qemu-aarch64-static"

cat > "$ROOTFS/etc/apk/repositories" <<EOF
$ALPINE_MIRROR/main
$ALPINE_MIRROR/community
EOF
# Let the ARM64 chroot resolve Alpine mirrors during provisioning.
if [ -f /etc/resolv.conf ]; then
  cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
fi

mkdir -p "$ROOTFS/usr/local/sbin" "$ROOTFS/etc/profile.d"

cat > "$ROOTFS/etc/hostname" <<'EOF'
ath9k-vm
EOF

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
Alpine ARM64 WiFi VM

This is a guest Linux VM. USB devices are attached by the Android/Termux launcher.
Use /usr/local/sbin/wifi-diagnose for non-destructive device diagnostics.
EOF

cat > "$ROOTFS/usr/local/sbin/wifi-diagnose" <<'EOF'
#!/bin/sh
set -u
printf '%s\n' '=== kernel ==='
uname -a
printf '%s\n' '=== USB ==='
if command -v lsusb >/dev/null 2>&1; then lsusb; else echo 'lsusb unavailable'; fi
printf '%s\n' '=== ath9k_htc module ==='
if command -v modinfo >/dev/null 2>&1; then modinfo ath9k_htc 2>&1 || true; fi
printf '%s\n' '=== interfaces ==='
if command -v iw >/dev/null 2>&1; then iw dev 2>&1 || true; else ip link 2>&1 || true; fi
printf '%s\n' '=== regulatory state ==='
if command -v iw >/dev/null 2>&1; then iw reg get 2>&1 || true; fi
printf '%s\n' '=== recent kernel log ==='
dmesg | tail -n 80 2>&1 || true
EOF
chmod 0755 "$ROOTFS/usr/local/sbin/wifi-diagnose"

cat > "$ROOTFS/etc/profile.d/wifi-vm.sh" <<'EOF'
export LANG=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
alias ll='ls -alF'
EOF

# Add tools through the guest's own apk, using QEMU user emulation.
# This is intentionally limited to diagnostics and the aircrack-ng suite; no attack automation is installed.
# Use the ARM64 apk binary directly under QEMU user-mode. This avoids host chroot
# restrictions and skips package scripts that require unshare during image construction.
qemu-aarch64-static -L "$ROOTFS" "$ROOTFS/sbin/apk" --root "$ROOTFS" --arch aarch64 update
qemu-aarch64-static -L "$ROOTFS" "$ROOTFS/sbin/apk" --root "$ROOTFS" --arch aarch64 --no-cache --no-scripts add \
  alpine-base bash ca-certificates iproute2 iw usbutils kmod ethtool wireless-tools \
  aircrack-ng tcpdump busybox-extras openssh-client mkinitfs pax-utils scanelf binutils which cpio gzip
# Keep the split executable present after apk has completed its package transaction.
if [ -f "$ARTIFACTS/scanelf-1.3.9-r1.apk" ]; then
  tar --warning=no-unknown-keyword -xzf "$ARTIFACTS/scanelf-1.3.9-r1.apk" -C "$ROOTFS"
fi
# Under PRoot, Alpine's external `which` cannot see emulated executables;
# lddtree's shell-level command lookup works correctly.
sed -i 's/which scanelf/command -v scanelf/; s/which objdump/command -v objdump/; s/which readelf/command -v readelf/' "$ROOTFS/usr/bin/lddtree"

# Use the kernel from the same linux-lts APK as the modules.
cp -f "$ROOTFS/boot/vmlinuz-lts" "$GUEST/vmlinuz-lts"
# Generate an initramfs from the matching module tree. PRoot provides the guest
# root while QEMU user-mode executes the aarch64 mkinitfs script.
mkdir -p "$GUEST/build-output"
proot -0 -r "$ROOTFS" -b "$GUEST/build-output:/build" \
  -q /usr/bin/qemu-aarch64-static /sbin/mkinitfs -F 'base virtio ext4 usb' \
  -o /build/initramfs-lts 6.18.44-0-lts
cp -f "$GUEST/build-output/initramfs-lts" "$GUEST/initramfs-lts"
rm -rf "$GUEST/build-output"
rm -f "$ROOTFS/usr/bin/qemu-aarch64-static" "$ROOTFS/tmp/provision.sh"

# Configure a direct root login shell for QEMU's ARM virt console. The `-l`
# flag only loads /etc/profile; it does not invoke a username/password login.
# SSH is not enabled by default.
cat > "$ROOTFS/etc/inittab" <<'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
ttyAMA0::respawn:/bin/sh -l
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF
# Keep the documented first local root login empty in both credential databases.
sed -i 's/^root:[^:]*:/root::/' "$ROOTFS/etc/passwd"
sed -i 's/^root:[^:]*:/root::/' "$ROOTFS/etc/shadow"
# Alpine/BusyBox expects a standard nine-field shadow record. Normalize the
# root entry so passwd updates /etc/shadow and later login accepts the hash.
awk -F: -v OFS=: '$1 == "root" { print $1,$2,($3==""?"0":$3),($4==""?"0":$4),($5==""?"99999":$5),($6==""?"7":$6),$7,$8,$9; next } { print }' "$ROOTFS/etc/shadow" > "$ROOTFS/etc/shadow.normalized"
mv "$ROOTFS/etc/shadow.normalized" "$ROOTFS/etc/shadow"
# BusyBox login refuses root on serial terminals that are absent from securetty,
# even when /etc/shadow contains a valid or empty password.
grep -qxF 'ttyAMA0' "$ROOTFS/etc/securetty" || printf '%s\n' 'ttyAMA0' >> "$ROOTFS/etc/securetty"
chmod 0600 "$ROOTFS/etc/shadow"
rm -f "$ROOTFS/etc/ssh/sshd_config" 2>/dev/null || true

# mke2fs reads the source tree as the current user. APKs contain a few
# setuid helpers with no owner-read bit; add only the read/search bits needed
# to copy them into the image.
find "$ROOTFS" -type d -exec chmod u+rx {} +
find "$ROOTFS" -type f ! -readable -exec chmod u+r {} +

# Build a sparse ext4 disk containing the complete rootfs.
rm -f "$DISK"
truncate -s "$DISK_SIZE" "$DISK"
mke2fs -q -F -t ext4 -L ath9k-vm -d "$ROOTFS" "$DISK"

# Remove build-only rootfs to keep the distribution small unless debugging is requested.
if [ "${KEEP_ROOTFS:-0}" != "1" ]; then
  rm -rf "$ROOTFS"
fi
sha256sum "$DISK" "$GUEST/vmlinuz-lts" "$GUEST/initramfs-lts" > "$GUEST/SHA256SUMS"

echo "[7/7] Built image: $DISK"
ls -lh "$DISK" "$GUEST/vmlinuz-lts" "$GUEST/initramfs-lts" "$GUEST/SHA256SUMS"
