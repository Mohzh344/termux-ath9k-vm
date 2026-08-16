#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

pkg update
pkg install -y qemu-system-aarch64-headless termux-api
chmod 0700 "$BASE_DIR"/bin/*.sh

for f in "$BASE_DIR/guest/alpine-ath9k.img" "$BASE_DIR/guest/vmlinuz-lts" "$BASE_DIR/guest/initramfs-lts"; do
  [ -s "$f" ] || { echo "missing required file: $f" >&2; exit 1; }
done

if [ -f "$BASE_DIR/guest/SHA256SUMS" ]; then
  (cd "$BASE_DIR/guest" && sha256sum -c SHA256SUMS)
fi

echo "Installed. Start without USB:"
echo "  $BASE_DIR/bin/launch-vm.sh"
echo "Attach AR9271 direct:"
echo "  termux-usb -l"
echo "  $BASE_DIR/bin/usb-attach-direct.sh /dev/bus/usb/BBB/DDD"
