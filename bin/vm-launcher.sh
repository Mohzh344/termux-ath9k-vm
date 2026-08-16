#!/data/data/com.termux/files/usr/bin/bash
# Additive unified launcher: legacy scripts remain available for advanced use.
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONF="$BASE_DIR/.vm-launcher.conf"
RUN_DIR="$BASE_DIR/run"
MONITOR="$RUN_DIR/qemu-monitor.sock"
CONSOLE="$RUN_DIR/qemu-console.sock"
PIDFILE="$RUN_DIR/qemu.pid"
LOGFILE="$RUN_DIR/qemu-usb.log"
USB_PID=""; STARTED=0
say(){ printf '\n==> %s\n' "$*"; }
warn(){ printf '\nWARNING: %s\n' "$*" >&2; }
die(){ printf '\nERROR: %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Missing $1. $2"; }
valid_ram(){ [[ "$1" =~ ^[0-9]{3,5}$ ]] && (( $1>=256 && $1<=32768 )); }
valid_smp(){ [[ "$1" =~ ^[0-9]{1,2}$ ]] && (( $1>=1 && $1<=32 )); }
safe_unlink(){ rm -f -- "$@"; }
qemu_running(){ pgrep -f '[q]emu-system-aarch64' >/dev/null 2>&1; }
monitor(){ [ -S "$MONITOR" ] && printf '%s\n' "$1" | socat - "UNIX-CONNECT:$MONITOR" >/dev/null 2>&1; }
load_conf(){
  SAVED_RAM=768; SAVED_SMP=1; SAVED_DISK=""
  [ -f "$CONF" ] || return
  local x
  x="$(sed -n 's/^RAM=//p' "$CONF"|head -1)"; valid_ram "$x" && SAVED_RAM="$x"
  x="$(sed -n 's/^SMP=//p' "$CONF"|head -1)"; valid_smp "$x" && SAVED_SMP="$x"
  x="$(sed -n 's|^DISK=||p' "$CONF"|head -1)"; [ -f "$x" ] && SAVED_DISK="$x"
}
save_conf(){ umask 077; printf '# vm-launcher settings\nRAM=%s\nSMP=%s\nDISK=%s\n' "$RAM" "$SMP" "$DISK" > "$CONF"; }
cleanup(){
  local rc=$? qpid="" n=0
  trap - EXIT INT TERM
  if (( STARTED )); then
    say 'Requesting clean guest shutdown…'; monitor system_powerdown || true
    while ((n<20)); do qpid="$(cat "$PIDFILE" 2>/dev/null||true)"; { [ -z "$qpid" ] || ! kill -0 "$qpid" 2>/dev/null; } && break; sleep 1; ((n+=1)); done
    qpid="$(cat "$PIDFILE" 2>/dev/null||true)"
    if [ -n "$qpid" ] && kill -0 "$qpid" 2>/dev/null; then warn 'Shutdown timeout: terminating QEMU.'; kill -TERM "$qpid" 2>/dev/null||true; sleep 2; kill -KILL "$qpid" 2>/dev/null||true; fi
    [ -z "$USB_PID" ] || kill -TERM "$USB_PID" 2>/dev/null||true
  fi
  safe_unlink "$MONITOR" "$CONSOLE" "$PIDFILE"
  exit "$rc"
}
trap cleanup EXIT INT TERM
repair_securetty(){
  local marker="$BASE_DIR/.securetty-$(basename "$DISK").ttyAMA0-v1" tmp backup got
  [ -f "$marker" ] && return
  need debugfs 'Install e2fsprogs once: pkg install e2fsprogs'
  qemu_running && die 'Stop the existing VM before the offline guest-image repair.'
  tmp="$(mktemp "$RUN_DIR/securetty.XXXXXX")"
  debugfs -R "dump -p /etc/securetty $tmp" "$DISK" >/dev/null 2>&1 || : > "$tmp"
  if grep -qxF ttyAMA0 "$tmp"; then
    safe_unlink "$tmp"
    printf 'ttyAMA0 already present; offline verification complete\n' > "$marker"
    say 'Verified: ttyAMA0 is already permanently present in guest /etc/securetty.'
    return
  fi
  say 'One-time repair: adding ttyAMA0 to guest /etc/securetty'
  printf 'ttyAMA0\n' >> "$tmp"
  backup="$BASE_DIR/guest/$(basename "$DISK").before-securetty-$(date +%Y%m%d-%H%M%S).bak"
  say 'Creating sparse disk backup before the one-time repair…'
  cp --sparse=always "$DISK" "$backup" || { safe_unlink "$tmp" "$backup"; die 'Backup failed; image remains unchanged.'; }
  debugfs -w -R 'unlink /etc/securetty' "$DISK" >/dev/null 2>&1 || true
  debugfs -w -R "write $tmp /etc/securetty" "$DISK" >/dev/null
  debugfs -w -R 'set_inode_field /etc/securetty uid 0' "$DISK" >/dev/null
  debugfs -w -R 'set_inode_field /etc/securetty gid 0' "$DISK" >/dev/null
  debugfs -w -R 'set_inode_field /etc/securetty mode 0100644' "$DISK" >/dev/null
  debugfs -w -R 'set_inode_field /etc/shadow mode 0100600' "$DISK" >/dev/null 2>&1 || true
  safe_unlink "$tmp"
  got="$(debugfs -R 'cat /etc/securetty' "$DISK" 2>/dev/null||true)"
  grep -qxF ttyAMA0 <<<"$got" || die "Repair verification failed. Restore $backup before booting."
  printf 'ttyAMA0 verified\nbackup=%s\n' "$backup" > "$marker"
  say "Verified permanent securetty fix. Backup: $(basename "$backup")"
}
choose_resources(){
  load_conf; local a i default=1; while :; do read -r -p "RAM in MiB [$SAVED_RAM] (Lite recommended): " a; RAM="${a:-$SAVED_RAM}"; valid_ram "$RAM" && break; warn 'Use an integer from 256 to 32768.'; done
  while :; do read -r -p "Virtual CPUs / SMP [$SAVED_SMP] (1 recommended for TCG): " a; SMP="${a:-$SAVED_SMP}"; valid_smp "$SMP" && break; warn 'Use an integer from 1 to 32.'; done
  local -a images=(); mapfile -t images < <(find "$BASE_DIR/guest" -maxdepth 1 -type f -name '*.img' -print|sort); ((${#images[@]}))||die 'No guest .img image found.'
  for i in "${!images[@]}"; do [ "${images[$i]}" = "$SAVED_DISK" ]&&default=$((i+1)); done
  printf '\nExisting disk images (automatic resizing is intentionally disabled):\n'; for i in "${!images[@]}"; do printf '  %d) %s (%s used)\n' "$((i+1))" "$(basename "${images[$i]}")" "$(du -h "${images[$i]}"|awk '{print $1}')"; done
  while :; do read -r -p "Choose image [$default]: " a; a="${a:-$default}"; [[ "$a" =~ ^[0-9]+$ ]]&&((a>=1&&a<=${#images[@]}))&&{ DISK="${images[$((a-1))]}"; break; }; warn 'Choose a listed number.'; done
  save_conf
}
choose_usb(){
  need termux-usb 'Install Termux:API and termux-api first.'
  local raw a; raw="$(termux-usb -l 2>&1)"||die "termux-usb -l failed: $raw"
  local -a dev=(); mapfile -t dev < <(printf %s "$raw"|tr -d '[]" '|tr , '\n'|sed '/^$/d')
  ((${#dev[@]}))||{ USE_USB=0; say 'No USB device detected; using direct terminal console.'; return; }
  if ((${#dev[@]} == 1)); then
    USB_DEVICE="${dev[0]}"; USE_USB=1
    say "One USB device detected; selecting it automatically: $USB_DEVICE"
    return
  fi
  printf '\nAndroid-visible USB devices:\n'; local i; for i in "${!dev[@]}"; do printf '  %d) %s\n' "$((i+1))" "${dev[$i]}"; done; printf '  0) No USB\n'
  while :; do read -r -p "USB device [1]: " a; a="${a:-1}"; [ "$a" = 0 ]&&{ USE_USB=0; return; }; [[ "$a" =~ ^[0-9]+$ ]]&&((a>=1&&a<=${#dev[@]}))&&{ USB_DEVICE="${dev[$((a-1))]}"; USE_USB=1; return; }; warn 'Choose 0 or a listed number.'; done
}
start_plain(){ say "Booting without USB: ${RAM}MiB, ${SMP} CPU(s), $(basename "$DISK")"; STARTED=1; RAM="$RAM" SMP="$SMP" DISK="$DISK" MONITOR="$MONITOR" PIDFILE="$PIDFILE" TCG_THREAD="${TCG_THREAD:-auto}" "$BASE_DIR/bin/launch-vm.sh"; }
start_usb(){
  say "Requesting Android USB permission for $USB_DEVICE…"; termux-usb -r "$USB_DEVICE" >/dev/null||die 'Android USB permission was denied.'
  say 'Starting QEMU inside termux-usb and waiting for the console socket…'
  RAM="$RAM" SMP="$SMP" DISK="$DISK" MONITOR="$MONITOR" CONSOLE_SOCKET="$CONSOLE" PIDFILE="$PIDFILE" TCG_THREAD="${TCG_THREAD:-auto}" termux-usb -E -e "$BASE_DIR/bin/qemu-direct-inner.sh" "$USB_DEVICE" >"$LOGFILE" 2>&1 & USB_PID=$!; STARTED=1
  local n; for n in $(seq 1 60); do [ -S "$CONSOLE" ]&&break; kill -0 "$USB_PID" 2>/dev/null||{ sed -n '1,120p' "$LOGFILE" >&2||true; die 'USB/QEMU exited before console was ready.'; }; sleep 1; done
  [ -S "$CONSOLE" ]||{ sed -n '1,120p' "$LOGFILE" >&2||true; die 'Timed out waiting for VM console.'; }
  say 'VM is up. Serial console attached; Ctrl+C requests clean shutdown.'; socat -,raw,echo=0 "UNIX-CONNECT:$CONSOLE"
}
main(){
  [ -t 0 ]&&[ -t 1 ]||die 'Run from an interactive Termux terminal.'; mkdir -p "$RUN_DIR"; qemu_running&&die 'A QEMU VM is already running; launcher will not disturb it.'
  need qemu-system-aarch64 'Install qemu-system-aarch64-headless first.'; need socat 'Install socat first.'; safe_unlink "$MONITOR" "$CONSOLE" "$PIDFILE"
  say 'Termux Alpine Wi-Fi VM — unified launcher'; choose_resources; repair_securetty; choose_usb; ((USE_USB))&&start_usb||start_plain
}
main "$@"
