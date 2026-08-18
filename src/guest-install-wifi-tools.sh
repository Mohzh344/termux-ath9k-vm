#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo 'Run as root.' >&2
  exit 1
fi

apk update
apk add --no-cache aircrack-ng tcpdump hostapd wireless-regdb iw usbutils kmod ethtool wireless-tools

cat >/etc/wifi-tools-install-status <<'EOF'
base=aircrack-ng,tcpdump,hostapd,wireless-regdb,iw,usbutils,kmod,ethtool,wireless-tools
hcx=not-installed; use BUILD_HCX=1 for source build
wps=not-installed; use INSTALL_WPS_TOOLS=1 only when explicitly needed
EOF

if [ "${BUILD_HCX:-0}" = 1 ]; then
  apk add --no-cache build-base openssl-dev zlib-dev curl-dev libpcap-dev libnl3-dev linux-headers
  work=/tmp/wifi-tools-build
  rm -rf "$work"
  mkdir -p "$work"
  fetch() { curl -fL --retry 3 --connect-timeout 20 -o "$2" "$1"; }
  fetch https://github.com/ZerBea/hcxdumptool/releases/download/7.1.2/hcxdumptool-7.1.2.tar.gz "$work/hcxdumptool.tar.gz"
  fetch https://github.com/ZerBea/hcxtools/releases/download/7.1.2/hcxtools-7.1.2.tar.gz "$work/hcxtools.tar.gz"
  mkdir "$work/hcxdumptool" "$work/hcxtools"
  tar -xzf "$work/hcxdumptool.tar.gz" -C "$work/hcxdumptool" --strip-components=1
  tar -xzf "$work/hcxtools.tar.gz" -C "$work/hcxtools" --strip-components=1
  make -C "$work/hcxdumptool" -j1
  install -m 0755 "$work/hcxdumptool/hcxdumptool" /usr/bin/hcxdumptool
  make -C "$work/hcxtools" -j1
  for f in "$work/hcxtools"/*; do
    [ -x "$f" ] && install -m 0755 "$f" "/usr/bin/$(basename "$f")" || true
  done
  sed -i 's/^hcx=.*/hcx=7.1.2/' /etc/wifi-tools-install-status
  rm -rf "$work"
  apk del build-base openssl-dev zlib-dev curl-dev libpcap-dev libnl3-dev linux-headers || true
fi

printf '%s\n' 'Installed base Wi-Fi runtime tools.' 'No capture/deauthentication/WPS action is started automatically.'
