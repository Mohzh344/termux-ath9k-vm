#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit(f"usage: {sys.argv[0]} /path/to/build-image.sh")
path = Path(sys.argv[1])
text = path.read_text()
needle = "sed -i 's/^root:[^:]*:/root::/' \"$ROOTFS/etc/shadow\""
insert = needle + "\n" + (
    "awk -F: -v OFS=: '$1 == \"root\" { print $1,$2,($3==\"\"?\"0\":$3),($4==\"\"?\"0\":$4),($5==\"\"?\"99999\":$5),($6==\"\"?\"7\":$6),$7,$8,$9; next } { print }' "
    '"$ROOTFS/etc/shadow" > "$ROOTFS/etc/shadow.normalized"'
    "\n"
    'mv "$ROOTFS/etc/shadow.normalized" "$ROOTFS/etc/shadow"'
)
if "shadow.normalized" not in text:
    if needle not in text:
        raise SystemExit("root shadow sed line not found")
    text = text.replace(needle, insert, 1)
    path.write_text(text)
