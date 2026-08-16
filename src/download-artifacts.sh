#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$PROJECT_DIR/artifacts"
BASE="https://dl-cdn.alpinelinux.org/alpine/v3.24"
mkdir -p "$ARTIFACTS"

fetch() {
  local name="$1" url="$2"
  if [ ! -s "$ARTIFACTS/$name" ]; then
    echo "downloading $name"
    curl --fail --location --proto "=https" --tlsv1.2 --retry 3 -o "$ARTIFACTS/$name" "$url"
  else
    echo "exists $name"
  fi
}

fetch alpine-minirootfs-3.24.1-aarch64.tar.gz "$BASE/releases/aarch64/alpine-minirootfs-3.24.1-aarch64.tar.gz"
fetch linux-lts-6.18.44-r0.apk "$BASE/main/aarch64/linux-lts-6.18.44-r0.apk"
fetch linux-firmware-ath9k_htc-20260519-r0.apk "$BASE/main/aarch64/linux-firmware-ath9k_htc-20260519-r0.apk"
fetch mkinitfs-3.14.0-r0.apk "$BASE/main/aarch64/mkinitfs-3.14.0-r0.apk"
fetch scanelf-1.3.9-r1.apk "$BASE/main/aarch64/scanelf-1.3.9-r1.apk"

sha256sum "$ARTIFACTS"/* | tee "$ARTIFACTS/SHA256SUMS"
