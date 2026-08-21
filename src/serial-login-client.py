#!/usr/bin/env python3
"""Capture a QEMU Unix serial socket and submit a deterministic login test."""
from __future__ import annotations

import select
import socket
import sys
import time
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit("usage: serial-login-client.py SOCKET OUTPUT login|login-empty")

socket_path = sys.argv[1]
output_path = Path(sys.argv[2])
mode = sys.argv[3]
if mode not in {"login", "login-empty"}:
    raise SystemExit("mode must be login or login-empty")

payload = b"root\ntestpass123\n" if mode == "login" else b"root\n\n"
deadline = time.monotonic() + 125.0
send_at = time.monotonic() + 55.0
captured = bytearray()

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as channel:
    channel.settimeout(10.0)
    channel.connect(socket_path)
    channel.setblocking(False)
    submitted = False
    while time.monotonic() < deadline:
        now = time.monotonic()
        if not submitted and now >= send_at:
            channel.sendall(payload)
            submitted = True
        readable, _, _ = select.select([channel], [], [], 0.5)
        if readable:
            try:
                data = channel.recv(8192)
            except BlockingIOError:
                continue
            if not data:
                break
            captured.extend(data)

output_path.write_bytes(bytes(captured))
if not submitted:
    raise SystemExit("login input was not submitted before timeout")
