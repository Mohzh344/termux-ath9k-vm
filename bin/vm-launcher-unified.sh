#!/usr/bin/env bash
# Unified front door for the combined Full + Lite release.
# Existing Full/Lite launchers remain untouched and are delegated to.
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FULL_DIR="${FULL_DIR:-$BASE_DIR/full}"
LITE_DIR="${LITE_DIR:-$BASE_DIR/lite}"
DRY_RUN=0
NONINTERACTIVE=0
VARIANT="${VM_VARIANT:-}"
USB_DEVICE=""
USB_PID=""
EXPLICIT_DIR=""

say(){ printf '\n==> %s\n' "$*"; }
warn(){ printf '\nWARNING: %s\n' "$*" >&2; }
die(){ printf '\nERROR: %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Missing $1. $2"; }

usage(){
  cat <<'EOF'
Usage: bin/vm-launcher.sh [options]

Unified launcher for the combined Full + Lite bundle.

Options:
  --dry-run          Detect and print the selected path without starting QEMU.
  --non-interactive  Never prompt; require explicit selection when ambiguous.
  --full             Select the complete Full bundle when available.
  --lite             Select the complete Lite bundle when available.
  --help             Show this help.

Explicit environment variables are preserved, including DISK, KERNEL, INITRD,
RAM, SMP, PROFILE, KERNEL_TIER, USB_MODE, TCG_THREAD, SERIAL_MODE, and SHARE_MODE.
EOF
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --non-interactive) NONINTERACTIVE=1 ;;
    --full) VARIANT=full ;;
    --lite) VARIANT=lite ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
  shift
done

required_full(){
  local d="$1"
  [ -f "$d/guest/alpine-ath9k.img" ] &&
  [ -f "$d/guest/vmlinuz-lts" ] &&
  [ -f "$d/guest/initramfs-lts" ]
}
required_lite(){
  local d="$1"
  [ -f "$d/guest/alpine-ath9k-v030-lite.img" ] &&
  [ -f "$d/guest/vmlinuz-tiny" ] &&
  [ -f "$d/guest/vmlinuz-safe" ] &&
  [ -f "$d/guest/vmlinuz-lts-lite" ] &&
  [ -f "$d/guest/initramfs-lts-lite" ]
}

full_missing(){
  local d="$1" f; for f in guest/alpine-ath9k.img guest/vmlinuz-lts guest/initramfs-lts; do
    [ -f "$d/$f" ] || printf '  missing Full: %s\n' "$d/$f" >&2
  done
}
lite_missing(){
  local d="$1" f; for f in guest/alpine-ath9k-v030-lite.img guest/vmlinuz-tiny guest/vmlinuz-safe guest/vmlinuz-lts-lite guest/initramfs-lts-lite; do
    [ -f "$d/$f" ] || printf '  missing Lite: %s\n' "$d/$f" >&2
  done
}

# Support the combined archive layout and a developer checkout containing both
# guest sets at its root. Explicit bundle directories are authoritative; this
# also prevents unrelated leftovers elsewhere in a test or wrapper environment
# from creating a false ambiguous result.
candidates_full=()
candidates_lite=()
if [ -n "${FULL_DIR+x}" ] || [ -n "${LITE_DIR+x}" ]; then
  scan_dirs=("$FULL_DIR" "$LITE_DIR")
else
  scan_dirs=("$FULL_DIR" "$LITE_DIR" "$BASE_DIR" "$BASE_DIR/termux-ath9k-vm" "$BASE_DIR/termux-ath9k-vm-lite")
fi
for d in "${scan_dirs[@]}"; do
  [ -d "$d" ] || continue
  if required_full "$d"; then candidates_full+=("$d"); fi
  if required_lite "$d"; then candidates_lite+=("$d"); fi
done
# De-duplicate candidates while preserving order.
unique(){ awk '!seen[$0]++'; }
if ((${#candidates_full[@]})); then mapfile -t candidates_full < <(printf '%s\n' "${candidates_full[@]}" | unique); else candidates_full=(); fi
if ((${#candidates_lite[@]})); then mapfile -t candidates_lite < <(printf '%s\n' "${candidates_lite[@]}" | unique); else candidates_lite=(); fi

select_variant(){
  local nfull=${#candidates_full[@]} nlite=${#candidates_lite[@]}
  if [ -n "${DISK:-}" ]; then
    [ -f "$DISK" ] || die "Explicit DISK does not exist: $DISK"
    EXPLICIT_DIR="$(cd "$(dirname "$(dirname "$DISK")")" && pwd)"
    case "$(basename "$DISK")" in
      alpine-ath9k.img) VARIANT=full ;;
      alpine-ath9k-v030-lite.img) VARIANT=lite ;;
      *) [ -n "$VARIANT" ] || die 'Cannot infer Full/Lite from explicit DISK name; use VM_VARIANT=full or VM_VARIANT=lite.' ;;
    esac
  fi
  if [ -n "${KERNEL_TIER:-}" ] && [ -z "$VARIANT" ]; then VARIANT=lite; fi
  if [ -n "$VARIANT" ]; then
    case "$VARIANT" in
      full) if [ -z "$EXPLICIT_DIR" ] && ((nfull==0)); then full_missing "$FULL_DIR"; die 'Full was requested but no complete Full bundle was found.'; fi ;;
      lite) if [ -z "$EXPLICIT_DIR" ] && ((nlite==0)); then lite_missing "$LITE_DIR"; die 'Lite was requested but no complete Lite bundle was found.'; fi ;;
      *) die 'VM_VARIANT/selection must be full or lite.' ;;
    esac
    return
  fi
  if ((nfull==1 && nlite==0)); then VARIANT=full; return; fi
  if ((nlite==1 && nfull==0)); then VARIANT=lite; return; fi
  if ((nfull==0 && nlite==0)); then
    warn 'No complete Full or Lite bundle was found. Nothing was built or deleted.'
    echo 'Expected Full: guest/alpine-ath9k.img + vmlinuz-lts + initramfs-lts' >&2
    echo 'Expected Lite: guest/alpine-ath9k-v030-lite.img + tiny + safe + lts + initramfs-lts-lite' >&2
    die 'Extract a release archive first, or run the appropriate build script explicitly.'
  fi
  if ((NONINTERACTIVE)); then die 'Both complete Full and Lite bundles were found; use --full, --lite, or VM_VARIANT.'; fi
  printf '\nDetected complete VM bundles:\n'
  printf '  1) Full — %s\n' "${candidates_full[0]}"
  printf '  2) Lite — %s\n' "${candidates_lite[0]}"
  local a
  while :; do
    read -r -p 'Choose bundle [2]: ' a
    a="${a:-2}"
    case "$a" in 1) VARIANT=full; return;; 2) VARIANT=lite; return;; *) warn 'Choose 1 or 2.';; esac
  done
}

bundle_dir(){
  if [ -n "$EXPLICIT_DIR" ]; then printf '%s\n' "$EXPLICIT_DIR"; elif [ "$VARIANT" = full ]; then printf '%s\n' "${candidates_full[0]}"; else printf '%s\n' "${candidates_lite[0]}"; fi
}

choose_lite_tier(){
  if [ -n "${KERNEL_TIER:-}" ]; then return; fi
  if ((NONINTERACTIVE)); then KERNEL_TIER=safe; return; fi
  printf '\nLite kernel tiers:\n'
  printf '  1) safe — recommended compatibility kernel (~7.0 MB)\n'
  printf '  2) tiny — smallest AR9271-focused kernel (~6.9 MB)\n'
  printf '  3) lts  — initramfs fallback if a custom tier fails\n'
  local a
  while :; do
    read -r -p 'Choose tier [1]: ' a
    a="${a:-1}"
    case "$a" in 1) KERNEL_TIER=safe; return;; 2) KERNEL_TIER=tiny; return;; 3) KERNEL_TIER=lts; return;; *) warn 'Choose 1, 2, or 3.';; esac
  done
}

choose_full_resources(){
  if [ -z "${RAM:-}" ]; then
    if ((NONINTERACTIVE)); then RAM=768
    else local a; read -r -p 'Full RAM in MiB [768]: ' a; RAM="${a:-768}"; fi
  fi
  if [ -z "${SMP:-}" ]; then
    if ((NONINTERACTIVE)); then SMP=1
    else local a; read -r -p 'Full virtual CPUs / SMP [1]: ' a; SMP="${a:-1}"; fi
  fi
}

choose_lite_profile(){
  if [ -n "${PROFILE:-}" ]; then return; fi
  if ((NONINTERACTIVE)); then PROFILE=wifi-only; return; fi
  printf '\nLite profiles: wifi-only (512M/1 CPU), balanced (768M/2), default (1024M/2), legacy (1536M/4).\n'
  local a
  read -r -p 'Profile [wifi-only]: ' a
  PROFILE="${a:-wifi-only}"
}

choose_usb(){
  if [ -n "${USB_MODE:-}" ]; then return; fi
  USB_MODE=none
  if ((NONINTERACTIVE)); then return; fi
  if ! command -v termux-usb >/dev/null 2>&1; then
    say 'termux-usb is unavailable; continuing without USB passthrough.'
    return
  fi
  local raw a
  raw="$(termux-usb -l 2>&1)" || { warn "termux-usb -l failed: $raw"; return; }
  local -a dev=()
  mapfile -t dev < <(printf '%s' "$raw" | tr -d '[]" ' | tr ',' '\n' | sed '/^$/d')
  if ((${#dev[@]}==0)); then say 'No Android-visible USB device found; continuing without USB.'; return; fi
  if ((${#dev[@]}==1)); then
    USB_DEVICE="${dev[0]}"
    read -r -p "Use USB device $USB_DEVICE? [Y/n]: " a
    case "${a:-Y}" in [Nn]*) return;; esac
    USB_MODE=direct
    return
  fi
  printf '\nAndroid-visible USB devices:\n'
  local i
  for i in "${!dev[@]}"; do printf '  %d) %s\n' "$((i+1))" "${dev[$i]}"; done
  printf '  0) No USB\n'
  while :; do
    read -r -p 'USB device [0]: ' a
    a="${a:-0}"
    [ "$a" = 0 ] && return
    if [[ "$a" =~ ^[0-9]+$ ]] && ((a>=1 && a<=${#dev[@]})); then USB_DEVICE="${dev[$((a-1))]}"; USB_MODE=direct; return; fi
    warn 'Choose 0 or a listed number.'
  done
}

print_plan(){
  local d="$1"
  if [ "$VARIANT" = full ]; then
    printf 'Detected=Full dir=%s disk=%s kernel=vmlinuz-lts initramfs=yes RAM=%s SMP=%s USB=%s\n' \
      "$d" "${DISK:-$d/guest/alpine-ath9k.img}" "${RAM:-768}" "${SMP:-1}" "${USB_MODE:-none}"
  else
    printf 'Detected=Lite dir=%s disk=%s tier=%s profile=%s RAM/SMP=profile-default USB=%s\n' \
      "$d" "${DISK:-$d/guest/alpine-ath9k-v030-lite.img}" "${KERNEL_TIER:-safe}" "${PROFILE:-wifi-only}" "${USB_MODE:-none}"
  fi
}

start_usb(){
  need termux-usb 'Install Termux:API and termux-api first.'
  need socat 'Install socat first for the USB console.'
  [ -n "$USB_DEVICE" ] || die 'USB_MODE=direct requires USB_DEVICE.'
  local d="$1" inner="$2" label="$3" console="$d/qemu-unified-console.sock" log="$d/qemu-unified-usb.log"
  mkdir -p "$d/run"
  rm -f "$console" "$d/qemu-monitor.sock" "$d/qemu-lite-monitor.sock" "$d/run/qemu.pid"
  termux-usb -r "$USB_DEVICE" >/dev/null || die 'Android USB permission was denied.'
  env VM_DIR="$d" PROFILE="${PROFILE:-wifi-only}" KERNEL_TIER="${KERNEL_TIER:-safe}" \
    DISK="${DISK:-}" KERNEL="${KERNEL:-}" INITRD="${INITRD:-}" RAM="${RAM:-}" SMP="${SMP:-}" \
    USB_MODE=direct SERIAL_MODE=unix CONSOLE_SOCKET="$console" PIDFILE="$d/run/qemu.pid" \
    termux-usb -E -e "$inner" "$USB_DEVICE" >"$log" 2>&1 & USB_PID=$!
  trap 'kill "$USB_PID" 2>/dev/null || true' INT TERM EXIT
  local n
  for n in $(seq 1 60); do [ -S "$console" ] && break; kill -0 "$USB_PID" 2>/dev/null || { sed -n '1,120p' "$log" >&2 || true; die "USB/QEMU exited before $label console was ready."; }; sleep 1; done
  [ -S "$console" ] || { sed -n '1,120p' "$log" >&2 || true; die "Timed out waiting for $label VM console."; }
  say "$label VM is up. Serial console attached; Ctrl+C requests shutdown."
  socat -,raw,echo=0 "UNIX-CONNECT:$console" || true
  kill "$USB_PID" 2>/dev/null || true
  wait "$USB_PID" 2>/dev/null || true
  trap - INT TERM EXIT
}

main(){
  [ -t 0 ] && [ -t 1 ] || NONINTERACTIVE=1
  select_variant
  local d; d="$(bundle_dir)"
  if [ "$VARIANT" = full ]; then choose_full_resources; else choose_lite_tier; choose_lite_profile; fi
  choose_usb
  print_plan "$d"
  ((DRY_RUN)) && exit 0
  if [ "$VARIANT" = full ]; then
    if [ "${USB_MODE:-none}" = direct ]; then
      start_usb "$d" "$d/bin/qemu-direct-inner.sh" Full
    else
      say 'Starting Full with the existing linux-lts + initramfs path.'
      full_args=("$d/bin/launch-vm.sh")
      env_args=("VM_DIR=$d" "DISK=${DISK:-$d/guest/alpine-ath9k.img}" "KERNEL=${KERNEL:-$d/guest/vmlinuz-lts}" "INITRD=${INITRD:-$d/guest/initramfs-lts}" "RAM=$RAM" "SMP=$SMP" "USB_MODE=${USB_MODE:-none}" "TCG_THREAD=${TCG_THREAD:-auto}" "SERIAL_MODE=${SERIAL_MODE:-stdio}" "SHARE_DIR=${SHARE_DIR:-$HOME}")
      exec env "${env_args[@]}" "${full_args[@]}"
    fi
  elif [ "${USB_MODE:-none}" = direct ]; then
    start_usb "$d" "$d/bin/qemu-lite-direct-inner.sh" Lite
  else
    say 'Starting Lite without USB passthrough.'
    lite_args=("$d/bin/launch-vm-lite.sh")
    env_args=("PROFILE=${PROFILE:-wifi-only}" "KERNEL_TIER=${KERNEL_TIER:-safe}" "DISK=${DISK:-$d/guest/alpine-ath9k-v030-lite.img}" "USB_MODE=${USB_MODE:-none}" "TCG_THREAD=${TCG_THREAD:-multi}")
    [ -z "${RAM:-}" ] || env_args+=("RAM=$RAM")
    [ -z "${SMP:-}" ] || env_args+=("SMP=$SMP")
    [ -z "${CPU_MODEL:-}" ] || env_args+=("CPU_MODEL=$CPU_MODEL")
    [ -z "${ENABLE_NET:-}" ] || env_args+=("ENABLE_NET=$ENABLE_NET")
    [ -z "${SHARE_MODE:-}" ] || env_args+=("SHARE_MODE=$SHARE_MODE")
    exec env "${env_args[@]}" "${lite_args[@]}"
  fi
}
main "$@"
