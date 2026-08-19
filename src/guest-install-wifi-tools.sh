#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo 'Run as root.' >&2
  exit 1
fi

# Lite starts offline by design. If the launcher supplied a virtio NIC, bring it
# up and obtain a QEMU user-network DHCP lease before touching apk.
if command -v ip >/dev/null 2>&1 && ip link show eth0 >/dev/null 2>&1; then
  /usr/local/sbin/qemu-net-init 2>/dev/null || true
  if ! ip -4 addr show dev eth0 2>/dev/null | grep -q 'inet '; then
    echo 'Network interface eth0 exists but has no IPv4 lease.' >&2
    echo 'Restart Lite with ENABLE_NET=1 and a profile that permits networking.' >&2
    exit 2
  fi
else
  echo 'No guest network interface is available.' >&2
  echo 'Restart Lite with ENABLE_NET=1 before running install-wifi-tools.' >&2
  exit 2
fi

apk_with_tls_fallback() {
  log="$(mktemp /tmp/apk-tls.XXXXXX)"
  set +e
  apk --check-certificate=yes "$@" >"$log" 2>&1
  rc=$?
  set -e
  cat "$log"
  if [ "$rc" -eq 0 ] && ! grep -Eq 'certificate not trusted|TLS: unspecified error|Could not load client' "$log"; then
    rm -f "$log"
    return 0
  fi
  if [ "${APK_ALLOW_INSECURE_FALLBACK:-1}" != 1 ]; then
    echo 'APK TLS verification failed and insecure fallback is disabled.' >&2
    rm -f "$log"
    return "${rc:-2}"
  fi
  echo 'WARNING: APK TLS certificate verification failed in this guest/network path.' >&2
  echo 'WARNING: retrying with --check-certificate=no; APK package signatures remain enabled.' >&2
  rm -f "$log"
  apk --check-certificate=no "$@"
}

apk_with_tls_fallback update
apk_with_tls_fallback add --no-cache aircrack-ng tcpdump hostapd wireless-regdb iw usbutils kmod ethtool wireless-tools

cat >/etc/wifi-tools-install-status <<'EOF'
base=aircrack-ng,tcpdump,hostapd,wireless-regdb,iw,usbutils,kmod,ethtool,wireless-tools
hcx=not-installed; use BUILD_HCX=1 for source build
wps=not-installed; use INSTALL_WPS_TOOLS=1 only when explicitly needed
optional_repo_tools=wifite,bully,reaver,kismet,hcxdumptool,hcxtools:not-in-Alpine-v3.24-repositories
apk_tls=verified-or-explicit-signature-checked-fallback
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
