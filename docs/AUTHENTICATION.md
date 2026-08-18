# Console authentication

## Default v0.3.0 behavior

Both v0.3.0 images use a local serial autologin on `ttyAMA0` by default. The login path is:

```text
QEMU serial console -> getty -n -l /usr/local/sbin/serial-autologin -> /bin/login -f root
```

There is no default password to guess, and the root account is locked for password authentication in the image. This avoids the v0.1.0 failure mode in which an empty password or a password reset did not produce a usable serial login. The image is intended to be local-only; it does not enable SSH by default.

The successful boot test must contain both of these markers:

```text
login[...]: root login on 'ttyAMA0'
(none):~#
```

## Running the VM

The recommended first run is:

```sh
IMAGE_VARIANT=lite KERNEL_TIER=safe PROFILE=wifi-only ./bin/launch-vm.sh
```

The Full image is selected explicitly:

```sh
IMAGE_VARIANT=full KERNEL_TIER=safe PROFILE=balanced ./bin/launch-vm.sh
```

## Optional password console

Password mode is not the default and the builder refuses to create it without an explicit `crypt(3)` hash. On a Linux host, generate a SHA-512 hash with:

```sh
openssl passwd -6
```

Then build a password-mode image by supplying the returned hash as an environment variable. Do not put the clear-text password in a shell history or a public script:

```sh
AUTOLOGIN=0 ROOT_PASSWORD_HASH='$6$...generated-hash...' \
  INSTALL_WIFI_TOOLS=0 ./src/build-image.sh guest/alpine-ath9k-v030-password.img
```

The builder then writes the supplied hash to `/etc/shadow`, changes the serial getty to the normal password prompt, and aborts if the hash is missing. The project does not publish a shared default password.

## Security boundary

Autologin is appropriate only when the QEMU serial console is controlled by the device owner. It must not be combined with an exposed SSH service, an untrusted 9p share, or network forwarding unless the operator adds an intentional authentication policy. The guest-side tools installer does not start Wi-Fi capture, deauthentication, WPS, or other security actions automatically.
