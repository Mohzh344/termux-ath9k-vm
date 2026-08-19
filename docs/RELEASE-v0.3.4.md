# v0.3.4 — Writable Full Root and Explicit Console Authentication Modes

## Release summary

`v0.3.4` fixes the remaining password-management problem in Full and adds explicit authentication choices for both Full and Lite. The default remains a direct local root console. Users who need a username/password prompt can now select BusyBox `getty` login mode, while an empty-password mode is available only for private local testing.

## Root cause of the Full password failure

The Full image was not failing because of the password hash or because BusyBox `login` was fundamentally broken. Its initramfs uses Alpine's default root mount option when `rootflags` is absent. That default is read-only:

```text
-o "${KOPT_rootflags:-ro}"
```

The Full launcher supplied `root=/dev/vda rw`, but did not supply `rootflags=rw`. Consequently, the initramfs mounted `/dev/vda` as `ro` before OpenRC started. `passwd` could read the account but could not persist a new value, producing errors such as `Read-only file system` or falling back to `/etc/passwd`.

The Full launchers now pass:

```text
root=/dev/vda rw rootflags=rw rootfstype=ext4 rootwait
```

This correction is applied to the unified Full adapter, the historical Full launcher, and the Full rescue launcher.

## Authentication modes

The unified launcher now supports three explicit modes:

| Mode | Behavior | Recommendation |
|---|---|---|
| `root-console` | init starts `/bin/sh -l` directly as root; no username/password prompt | Default and recommended for the private local QEMU console |
| `login` | init starts BusyBox `getty`; the user receives a username/password prompt and the existing root password is preserved | Use when a real login boundary is desired |
| `login-empty` | init starts BusyBox `getty` and deliberately clears root's password | Local testing only; never expose this console remotely |

The `-l` in `root-console` only loads `/etc/profile`; it does not invoke `/sbin/login` and does not ask for credentials. The `login` mode uses:

```text
ttyAMA0::respawn:/sbin/getty -L 0 ttyAMA0 vt100
```

The mode is applied offline to the stopped image before QEMU starts. The helper refuses to modify an image while QEMU is running and checks the image with `e2fsck -fn` afterward.

## Verified password behavior

On clean copies of Full and Lite, the test suite successfully performed the following sequence: entered the direct root console, invoked `login root` with the initially empty root password, ran `passwd`, entered a new password twice, returned to the shell, invoked `login root` again, entered the new password, verified UID 0, and shut down cleanly. Full now mounts the root filesystem writable, so password changes persist within the image.

The release does not enable SSH or any remote login service. The new login mode applies only to the local QEMU serial console and should not be treated as a network security boundary.

## Launcher examples

```sh
# Recommended direct root console
VM_VARIANT=lite AUTH_MODE=root-console ENABLE_NET=0 \
bash bin/vm-launcher.sh --non-interactive

# Username/password login using the existing root password
VM_VARIANT=full AUTH_MODE=login ENABLE_NET=0 \
bash bin/vm-launcher.sh --non-interactive

# Empty-password login for private local testing only
VM_VARIANT=lite AUTH_MODE=login-empty ENABLE_NET=0 \
bash bin/vm-launcher.sh --non-interactive
```

The interactive launcher offers the same three choices after selecting Full or Lite. `login-empty` is labeled as local testing only.

The release does not start monitor mode, capture, deauthentication, WPS, injection, or any other active wireless operation automatically.
