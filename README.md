<div id="top"></div>

<!-- PROJECT SHIELDS -->
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![GPL-2.0 License][license-shield]][license-url]

<!-- PROJECT LOGO -->
<br />
<div align="center">

<h3 align="center">Alpine Linux Cloud Images</h3>

  <p align="center">
    Cloud-init-ready, signed Alpine Linux images for OpenStack and Proxmox
    <br />
    <br />
    <a href="https://github.com/open-img-cloud/alpine-linux/issues">Report a bug</a>
    ·
    <a href="https://github.com/open-img-cloud/alpine-linux/issues">Request a feature</a>
  </p>
</div>

## About

This repo builds [Alpine Linux][alpine] cloud images on top of the
upstream `nocloud_alpine-*-cloudinit-r0.qcow2` artifacts published at
[dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/][upstream]
and customises them via `virt-customize` for OpenStack-style
infrastructures. Both **BIOS** (SeaBIOS) and **UEFI** (OVMF) firmware
variants are produced.

The build pipeline is shared with the rest of [`open-img-cloud`][org]:
this repo only ships the `VERSION`, `customize.sh`, `detect-upstream.sh`,
config files, and two thin caller workflows that delegate to the
reusable workflows in [`open-img-cloud/.github`][shared] (`@main`).

Customisations applied to the upstream rootfs:

- **cloud-init** datasource list pinned to `OpenStack` + `ConfigDrive`
  (no `NoCloud`, no `Ec2`), default user `alpine` (sudo NOPASSWD,
  ssh-key-only, `lock_passwd: False`)
- **qemu-guest-agent** added and enabled at boot (not in the upstream
  image)
- **Serial console** wired (`ttyS0,115200n8`) for cloud / hypervisor
  consoles, including `ttyS0` in `/etc/securetty`
- **`apk update && upgrade`** at build time, `/var/cache/apk` purged after
- **`virt-sysprep`** to clean transient state, then `virt-sparsify --compress`

Each release publishes:

- `alpine-<version>-{bios,uefi}-x86_64.qcow2`
- `*.sha256`, `*.sha1`, `*.md5` per-file
- `*.bundle` cosign sigstore-bundle (signature + cert + Rekor proof)
- `MANIFEST-bios.json` + `MANIFEST-uefi.json` (per-variant build metadata,
  including the builder image digest used to produce the qcow2)
- `index.html` directory listing

## Where to download

Public CDN, served via Cloudflare in front of an R2 bucket (mirror of
the source-of-truth Garage):

| URL pattern                                                                            | Cache policy                  |
|----------------------------------------------------------------------------------------|-------------------------------|
| `https://images.openimages.cloud/alpine-linux/<version>/<filename>`                    | `max-age=31536000, immutable` |
| `https://images.openimages.cloud/alpine-linux/latest/<filename>`                       | `max-age=300`                 |

Browse: [images.openimages.cloud/alpine-linux/latest/][latest]

## Verify before deploy

cosign 3.x:

```sh
sha256sum -c <filename>.sha256                    # integrity
cosign verify-blob \
    --bundle <filename>.bundle \
    --new-bundle-format \
    --certificate-identity-regexp '^https://github.com/open-img-cloud/\.github/\.github/workflows/build-libguestfs-image\.yml@' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    <filename>                                     # provenance
```

The certificate identity points at the **reusable** build workflow in
`open-img-cloud/.github` — that's where GitHub's OIDC binds the SAN for
keyless signing, regardless of which caller repo (`alpaquita-linux`,
`alpine-linux`, …) invoked it. To tie the artifact back to *this* repo's
commit, also check `MANIFEST-<variant>.json`: it pins the caller `commit`
SHA, the workflow run URL, and the builder image digest. A successful
`Verified OK` plus a matching MANIFEST proves the qcow2 was produced by
the open-img-cloud shared pipeline from the listed alpine-linux commit.

## How to use

### OpenStack

```sh
# Pull the qcow2 (replace <V> with the desired version, e.g. 3.23.4)
curl -fLO https://images.openimages.cloud/alpine-linux/<V>/alpine-<V>-bios-x86_64.qcow2

openstack image create \
    --disk-format qcow2 --container-format bare \
    --file alpine-<V>-bios-x86_64.qcow2 \
    'Alpine Linux (BIOS) <V>'
```

For UEFI hosts (newer OpenStack with OVMF, or `hw_firmware_type=uefi`),
use the `-uefi-` variant and set the image property:

```sh
openstack image create \
    --disk-format qcow2 --container-format bare \
    --file alpine-<V>-uefi-x86_64.qcow2 \
    --property hw_firmware_type=uefi \
    'Alpine Linux (UEFI) <V>'
```

### Proxmox VE

```sh
# Copy to Proxmox host
scp alpine-<V>-bios-x86_64.qcow2 root@proxmox:/var/lib/vz/template/iso/

# On Proxmox: create a cloud-init template from the disk (BIOS / SeaBIOS)
qm create <VMID> --name alpine-template --memory 1024 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk <VMID> alpine-<V>-bios-x86_64.qcow2 <STORAGE>
qm set <VMID> --scsihw virtio-scsi-pci --scsi0 <STORAGE>:vm-<VMID>-disk-0
qm set <VMID> --boot c --bootdisk scsi0
qm set <VMID> --ide2 <STORAGE>:cloudinit
qm set <VMID> --serial0 socket --vga serial0
qm set <VMID> --ciuser alpine --sshkeys ~/.ssh/authorized_keys --ipconfig0 ip=dhcp
```

For UEFI templates (q35 + OVMF), use the `-uefi-` variant and add
`--bios ovmf --efidisk0 <STORAGE>:0,efitype=4m,pre-enrolled-keys=0` to
the `qm create`/`qm set` commands.

## Release flow

1. **`watch.yml`** runs daily 06:23 UTC, calls `build/detect-upstream.sh`
   which scrapes the highest semver `X.Y.Z` from the `cloud/` directory
   listing.
2. If the version differs from the current `VERSION`, the workflow opens
   (or updates) a PR `auto/upstream-bump`.
3. Merging the PR + pushing a `v<VERSION>` tag fires `release.yml`,
   which calls the shared `build-libguestfs-image.yml@main` reusable
   workflow once per `firmware` (`bios`, `uefi`).
4. Each build downloads the upstream qcow2, runs `customize.sh`,
   sysprep, sparsify, signs, and uploads to Garage + R2 under
   `s3://alpine-linux/<version>/`. The `latest/` alias is replaced and
   Cloudflare cache for `latest/` is purged.

## Repository layout

```
VERSION                          single line, e.g. "3.23.4"
build/
  customize.sh                   virt-customize hook (qcow2 path as $1)
  detect-upstream.sh             prints latest upstream semver (highest in cloud/ listing)
  config/
    cloud.cfg                    cloud-init config copied to /etc/cloud/
    grub                         GRUB defaults with serial console
    serial-config.sh             enables ttyS0 in inittab + securetty
.github/workflows/
  release.yml                    calls build-libguestfs-image.yml on tag push
  watch.yml                      daily cron, calls upstream-watch.yml
.gitignore                       repo-local override for global build/ exclusion
LICENSE                          GPL-2.0
```

## Contributing

Fork, branch, PR. Keep changes focused; the customize hook in particular
is consumed by the shared pipeline so backward-compatible tweaks are
preferred over rewrites.

## License

Distributed under the GPL-2.0 License. See `LICENSE`.

## Contact

Kevin Allioli — kevin@stackops.ch · [@stackopshq](https://twitter.com/stackopshq)

Project: [open-img-cloud/alpine-linux](https://github.com/open-img-cloud/alpine-linux)

[alpine]: https://www.alpinelinux.org/
[upstream]: https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/
[org]: https://github.com/open-img-cloud
[shared]: https://github.com/open-img-cloud/.github
[latest]: https://images.openimages.cloud/alpine-linux/latest/

<!-- shields -->
[contributors-shield]: https://img.shields.io/github/contributors/open-img-cloud/alpine-linux.svg?style=for-the-badge
[contributors-url]: https://github.com/open-img-cloud/alpine-linux/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/open-img-cloud/alpine-linux.svg?style=for-the-badge
[forks-url]: https://github.com/open-img-cloud/alpine-linux/network/members
[stars-shield]: https://img.shields.io/github/stars/open-img-cloud/alpine-linux.svg?style=for-the-badge
[stars-url]: https://github.com/open-img-cloud/alpine-linux/stargazers
[issues-shield]: https://img.shields.io/github/issues/open-img-cloud/alpine-linux.svg?style=for-the-badge
[issues-url]: https://github.com/open-img-cloud/alpine-linux/issues
[license-shield]: https://img.shields.io/github/license/open-img-cloud/alpine-linux.svg?style=for-the-badge
[license-url]: https://github.com/open-img-cloud/alpine-linux/blob/main/LICENSE
