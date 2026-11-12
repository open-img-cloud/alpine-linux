<p align="center">
  <a href="https://openimages.cloud/images/alpine-linux/">
    <img src="https://openimages.cloud/img/og/alpine-linux.png" alt="Alpine Linux cloud image for OpenStack and Proxmox" width="720">
  </a>
</p>

<p align="center">
  <a href="https://openimages.cloud/images/alpine-linux/"><img alt="Latest version (BIOS)" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fimages.openimages.cloud%2Falpine-linux%2Flatest%2FMANIFEST-bios.json&query=%24.version&label=latest%20bios&color=2459c4&cacheSeconds=3600"></a>
  <a href="https://openimages.cloud/images/alpine-linux/"><img alt="Latest version (UEFI)" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fimages.openimages.cloud%2Falpine-linux%2Flatest%2FMANIFEST-uefi.json&query=%24.version&label=latest%20uefi&color=2459c4&cacheSeconds=3600"></a>
  <a href="https://github.com/open-img-cloud/alpine-linux/actions/workflows/release.yml"><img alt="Release" src="https://github.com/open-img-cloud/alpine-linux/actions/workflows/release.yml/badge.svg"></a>
  <a href="https://openimages.cloud/verify/"><img alt="Signed with Sigstore cosign" src="https://img.shields.io/badge/signed-Sigstore%20cosign-2459c4"></a>
  <a href="https://openimages.cloud/quality/"><img alt="Boot-tested on OpenStack" src="https://img.shields.io/badge/boot--tested-OpenStack-2459c4"></a>
  <a href="LICENSE"><img alt="License GPL-2.0" src="https://img.shields.io/badge/license-GPL--2.0-555"></a>
</p>

<p align="center">
  <a href="https://openimages.cloud/images/alpine-linux/"><b>Catalog page</b></a> ·
  <a href="https://images.openimages.cloud/alpine-linux/latest/">Download</a> ·
  <a href="https://openimages.cloud/verify/">Verify</a> ·
  <a href="https://github.com/open-img-cloud/docs">Documentation</a> ·
  <a href="https://github.com/open-img-cloud/alpine-linux/issues">Report an issue</a>
</p>

Alpine Linux cloud image (qcow2) for **OpenStack** and **Proxmox**: the official Alpine
`generic` cloud-init image, verified, made ready for both clouds with the same rules as every
[openimages.cloud](https://openimages.cloud) image, signed with Sigstore cosign and boot-tested
on a real OpenStack before it is published. Two firmware variants are built from each release.

## At a glance

| | |
|---|---|
| **Upstream** | [Alpine Linux](https://www.alpinelinux.org/) `generic_alpine-<version>-x86_64-<firmware>-cloudinit-r0.qcow2` from [dl-cdn.alpinelinux.org](https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/), checked against its `.sha512` |
| **Default user** | `alpine`, SSH key only, passwordless `sudo` |
| **Variants** | `bios`: legacy boot, works on any hypervisor. `uefi`: needs `hw_firmware_type=uefi` on OpenStack, OVMF on Proxmox |
| **Format** | qcow2, x86_64, root filesystem grown to the disk at first boot |
| **Version** | the Alpine point release, `X.Y.Z`, e.g. `3.24.1`; one manifest per variant, `MANIFEST-bios.json` and `MANIFEST-uefi.json` ([all versions](https://images.openimages.cloud/alpine-linux/versions.json)) |
| **Support** | follows the Alpine `latest-stable` branch: each new point release becomes a new image |

## Quick start

```sh
# Pick the variant: bios or uefi
VARIANT=bios
# Latest version and its file name, from the signed manifest of that variant
M=https://images.openimages.cloud/alpine-linux/latest/MANIFEST-$VARIANT.json
V=$(curl -fsS $M | jq -r .version); F=$(curl -fsS $M | jq -r .filename)
curl -fLO https://images.openimages.cloud/alpine-linux/$V/$F
```

<details>
<summary><b>OpenStack</b></summary>

BIOS variant:

```sh
openstack image create --disk-format qcow2 --container-format bare \
  --property os_distro=alpinelinux --property os_version="${V%.*}" \
  --property hw_qemu_guest_agent=yes --property os_admin_user=alpine \
  --file "$F" "Alpine Linux $V (BIOS)"
```

UEFI variant: same command, plus the firmware property:

```sh
openstack image create --disk-format qcow2 --container-format bare \
  --property os_distro=alpinelinux --property os_version="${V%.*}" \
  --property hw_qemu_guest_agent=yes --property os_admin_user=alpine \
  --property hw_firmware_type=uefi \
  --file "$F" "Alpine Linux $V (UEFI)"
```

The full property set (SCSI disk, multiqueue, quiesced snapshots) is on the
[catalog page](https://openimages.cloud/images/alpine-linux/) and in
[`index.json`](https://images.openimages.cloud/index.json). To keep images up to date
automatically, use [oic-sync](https://github.com/open-img-cloud/oic-sync).

</details>

<details>
<summary><b>Proxmox VE</b></summary>

The commands to create a cloud-init template from this image are on the
[catalog page](https://openimages.cloud/images/alpine-linux/). For the `uefi` variant, the VM
needs OVMF firmware (`--bios ovmf` and an EFI disk).

</details>

<details>
<summary><b>Verify the signature</b></summary>

```sh
curl -fLO https://images.openimages.cloud/alpine-linux/$V/$F.bundle
cosign verify-blob "$F" --bundle "$F.bundle" \
  --certificate-identity-regexp '^https://github.com/open-img-cloud/\.github/\.github/workflows/build-(libguestfs|dib|nix-flake|freebsd)-image\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

</details>

## What this image changes

On top of the official image, and nothing else:

- installs and enables `qemu-guest-agent` (filesystem freeze for snapshots, IP reporting);
- sets dhcpcd to `slaac hwaddr` instead of `slaac private`: Neutron only accepts the
  MAC-derived link-local address and finds the port from it, so with the default the instance
  never gets the IPv6 address of its port;
- adds an SSH drop-in that turns off password and keyboard-interactive authentication;
- enables a login on the serial console (`ttyS0`);
- adds the openimages.cloud cloud-init policy: config drive read first, then the metadata
  service; no root login, no SSH password;
- cleans package caches and machine identity so every instance starts fresh.

Packages are not upgraded at build time: the upstream root filesystem is sized too tightly for
a new kernel. Security fixes arrive with each Alpine point release; run `apk upgrade` after
deployment if you need them sooner.

Every release must pass the same [runtime contract](https://openimages.cloud/quality/) on
OpenStack: SSH with the injected key, cloud-init finished, DNS, hostname, root filesystem grown,
passwordless `sudo`, IPv6 address and egress.

## How releases happen

1. Every day at 06:23 UTC a watcher looks for a new upstream image and opens a pull request
   that bumps [`VERSION`](VERSION).
2. Merging it is all it takes: the release is tagged, both variants are built, signed,
   boot-tested and published, then `latest/` and the [catalog](https://openimages.cloud/images/)
   move to it.

This repository only holds what is specific to Alpine Linux: [`VERSION`](VERSION),
[`build/customize.sh`](build/customize.sh), [`build/config/`](build/config),
[`build/detect-upstream.sh`](build/detect-upstream.sh) and thin workflows calling the shared
pipeline in [`open-img-cloud/.github`](https://github.com/open-img-cloud/.github).

## License

The build tooling in this repository is under [GPL-2.0](LICENSE). The image keeps the licensing
terms of Alpine Linux (each package under its own license). Alpine Linux is a trademark of its
owner; this project is not affiliated with Alpine Linux.
