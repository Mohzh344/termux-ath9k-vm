# v0.3.0 Unified — Full + Lite Bundle

This release provides one downloadable archive containing both VM variants:

- **Full:** the canonical v0.3.0 Full bundle, using Alpine linux-lts with its initramfs and the original Full launch/USB/recovery paths.
- **Lite:** the additive v0.3.0-lite bundle, including the `tiny`, `safe`, and `lts` kernel choices for the AR9271/ath9k_htc-focused workflow.

## Recommended installation

1. Download `termux-ath9k-vm-full-lite-ready.tar.gz` and its `.sha256` file.
2. Verify the checksum with `sha256sum -c`.
3. Extract the archive in Termux.
4. Run `bash bin/install-termux.sh` once.
5. Run `./bin/vm-launcher.sh`.

The unified launcher detects complete Full and Lite bundles. If both are present, it asks which variant to launch. For Lite, it offers `safe`, `tiny`, and `lts`; `safe` is the recommended default. Explicit environment variables and command-line selection are preserved.

The launcher does not rebuild, delete, resize, or overwrite a disk image automatically. Build and benchmark scripts remain separate developer/advanced utilities.

## Integrity

SHA-256 for the attached archive:

```text
275d014c2ba225fd1548645f2e2a963ba4b3c0b538657e9e2f6f6b0437a54722
```

The original releases remain available for users who want only one variant:

- v0.3.0 Full
- v0.3.0-lite

Physical Android OTG and AR9271 passthrough still require validation on the target phone because release builds cannot emulate Termux:API USB permission handling or a real adapter.
