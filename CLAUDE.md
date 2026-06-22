# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **thin caller repo** in the `open-img-cloud` (OIC) org. It does *not* contain a build engine. It pins a `VERSION`, a `customize.sh` hook, an upstream-version detector, and config files, then delegates all heavy lifting (download, build, sign, publish) to the **reusable workflows** in [`open-img-cloud/.github`][shared] (`@main`). The actual qcow2 building runs in the org's `build-libguestfs-image.yml` reusable workflow on a KVM-enabled runner — never locally here.

The product: cloud-init-ready, cosign-signed Alpine Linux qcow2 images (BIOS + UEFI) built on top of upstream `generic_alpine-*-cloudinit-r0.qcow2` artifacts (upstream renamed the prefix from `nocloud_` to `generic_` around the 3.24 cycle), published to `images.openimages.cloud/alpine-linux/`.

## Architecture / control flow

The repo's logic only runs *inside* org reusable workflows. Two local entry points feed them:

1. **`build/detect-upstream.sh`** — prints the highest semver `X.Y.Z` found in the upstream `cloud/` directory listing (scrapes the `-x86_64-bios-` filename; UEFI tracks the same version). Pure `bash + curl + GNU sort -V/grep`, no KVM — it runs in the `upstream-watch.yml` reusable workflow. Keep it portable.
2. **`build/customize.sh`** — `virt-customize` hook, receives the qcow2 path as `$1`, runs in the builder container with `/dev/kvm`. Consumed by the shared pipeline, so prefer **backward-compatible tweaks over rewrites**.

`.github/workflows/`:
- **`watch.yml`** — daily cron (06:23 UTC) → calls `upstream-watch.yml@main` with `os_name: alpine-linux`. Opens/updates an `auto/upstream-bump` PR when upstream differs from `VERSION`.
- **`release.yml`** — fires on `v*` tag push (or manual dispatch). Resolves the version (input → tag → `VERSION` file), then runs `build-libguestfs-image.yml@main` once per `firmware` in a `[bios, uefi]` matrix. `variant` per job avoids MANIFEST/SHA collisions. `publish` is true only on push (tag) or explicit dispatch input.

**Release = merge the bump PR, then push a `v<VERSION>` tag.**

## Customization contract (what `customize.sh` does — and deliberately does NOT)

The upstream Alpine `generic_*-cloudinit-*` image already ships cloud-init, openssh-server, and a default user. Several things were tried and reverted (see git log) because upstream already handles them. **Do not re-add** without a concrete reason:

- **No `apk upgrade`** at build time — the Alpine cloud rootfs is tightly sized; pulling a new kernel (~70 MB) fails with "No space left on device". Patch level comes from `watch.yml` bumping `VERSION` daily; consumers `apk upgrade` post-deploy.
- **No cloud-init / openssh-server install** — already present.
- **No bootloader edits** — Alpine uses `extlinux` (BIOS) / GRUB stub (UEFI); the kernel cmdline already wires the serial console. Touching it risks a half-applied dual-bootloader config.
- **No networking/sshd/dhcpcd changes** — upstream image already boots and gets DHCP (reverted in `f0118aa`).

What it *does*: `apk add qemu-guest-agent` (~3 MB, not in upstream) + `rc-update add ... default`; copy in and run `config/serial-config.sh` (enables `ttyS0` getty in `/etc/inittab` + adds it to `/etc/securetty`); purge `/var/cache/apk` + temp dirs.

**cloud-init datasource policy** (datasource_list = OpenStack + ConfigDrive, disable_root, ssh_pwauth, etc.) is *no longer* maintained here. It's injected org-wide by the reusable workflow via `templates/cloud.cfg.d/99_oic-policy.cfg` as a drop-in *after* `customize.sh` runs. Do not reintroduce a full-replacement `cloud.cfg` in this repo (removed in `8e07a56`). The only file under `config/` is `serial-config.sh`.

## Working in this repo

- No build/lint/test you can run locally — there's no test suite and the build needs KVM + the org builder container. Validate by dry-run: trigger `release.yml` via `workflow_dispatch` with `publish: false`.
- Test the detector locally: `bash build/detect-upstream.sh` (needs network).
- `.gitignore` intentionally un-ignores `build/` (`!/build/`) to override a global OIC exclusion — keep it.
- Signature verification & deploy instructions (cosign, OpenStack, Proxmox) live in `README.md`.

[shared]: https://github.com/open-img-cloud/.github
