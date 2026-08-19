# v0.3.3 — Direct Root Login Shell and PATH Fix

## Release summary

`v0.3.3` fixes the console environment in both Full and Lite. The QEMU serial console still opens directly as `root` without asking for a username or password, but the respawn action now starts `/bin/sh -l` so Alpine BusyBox `ash` reads `/etc/profile` and `/etc/profile.d` automatically.

## What changed

### Login shell without a login prompt

The guest `/etc/inittab` entry is now:

```text
ttyAMA0::respawn:/bin/sh -l
```

This does **not** invoke `/sbin/login`, `getty`, SSH, or any password validation. It only passes the `-l` flag to the shell. The process remains the direct root console started by init, preserving the passwordless local-console design.

The Full and Lite images both receive this correction. The Full maintenance scripts included in the unified archive are updated as well, so a future image rebuild or emergency console repair does not silently restore the old non-login shell.

### PATH availability

The guest profile explicitly exports:

```sh
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
```

Commands installed under `/usr/local/bin` or `/usr/local/sbin` are therefore available immediately in the first console and after every respawn. This fixes the case where installed Wi-Fi utilities existed but could not be found from the interactive shell.

### Credentials remain unchanged

The patch does not create a password, change root authentication, or introduce a username/password login flow. The console remains local to the QEMU serial session. Remote login is not enabled by this change.

## Verification

The release was tested from a clean archive extraction. The test checks the exact `/etc/inittab` entry, verifies the PATH export, boots Full and Lite, confirms UID 0, confirms commands resolve through PATH, and reboots cleanly. It also runs the Lite filesystem consistency check with `e2fsck -fn`.

Use the following commands inside the guest for a manual check:

```sh
id -u
printf '%s\n' "$PATH"
command -v install-wifi-tools
command -v wifi-diagnose
cat /etc/inittab
```

Expected results include UID `0`, `/usr/local/bin` in `PATH`, and the line `ttyAMA0::respawn:/bin/sh -l`.

The release does not start monitor mode, capture, deauthentication, WPS, injection, or any other active wireless operation automatically.
