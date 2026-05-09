#!/usr/bin/env bash
# Customize hook called by the build-libguestfs-image reusable workflow.
# Receives the qcow2 path as $1. Runs inside the stackopshq builder
# container with /dev/kvm exposed.
#
# Alpine cloud images (the `nocloud_*-cloudinit-*` variant) ship with
# cloud-init, openssh, and a default user already configured. Our job is
# to:
#   - swap the datasource_list to OpenStack + ConfigDrive (no NoCloud /
#     no Ec2) so the image matches the openimages.cloud convention
#   - add qemu-guest-agent (not in the upstream image)
#   - wire the serial console (so cloud / hypervisor consoles work)
#   - apk upgrade for the latest patch level at release time
#
# We do NOT install cloud-init — it's already there.
# We do NOT install openssh-server — it's already there.

set -euo pipefail

QCOW2="${1:?usage: customize.sh <path-to-qcow2>}"
CONFIG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/config"

if [[ ! -f "$QCOW2" ]]; then
  echo "::error::qcow2 not found: $QCOW2" >&2
  exit 1
fi

echo "[customize] target: $QCOW2"
echo "[customize] config: $CONFIG_DIR"

# NOTE: Alpine cloud images ship with a tightly-sized rootfs — a full
# `apk upgrade` pulls a new kernel (~70 MB) and fails with "No space
# left on device". We skip upgrade at build time (alpaquita-style):
# upstream point releases cover security patches via watch.yml bumping
# VERSION daily, and consumers can `apk upgrade` post-deploy if they
# need fresher patches mid-release.
#
# `apk add qemu-guest-agent` is small (~3 MB) and fits comfortably.
#
# We do NOT touch the bootloader: Alpine cloud images use `extlinux`
# (BIOS) or a GRUB stub (UEFI). The serial console is already wired in
# the upstream kernel cmdline; we drop our /etc/default/grub override
# rather than risk a half-applied dual-bootloader config.
virt-customize -a "$QCOW2" \
  --run-command 'apk add --no-cache qemu-guest-agent dhcpcd' \
  --copy-in "${CONFIG_DIR}/cloud.cfg:/etc/cloud/" \
  --mkdir /usr/local/sbin \
  --copy-in "${CONFIG_DIR}/serial-config.sh:/usr/local/sbin/" \
  --run-command 'chmod +x /usr/local/sbin/serial-config.sh && /usr/local/sbin/serial-config.sh' \
  --copy-in "${CONFIG_DIR}/interfaces:/etc/network/" \
  --run-command 'rc-update add dhcpcd boot' \
  --run-command 'rc-update add sshd default' \
  --run-command 'rc-update add qemu-guest-agent default' \
  --run-command 'rm -rf /var/cache/apk/* /tmp/* /var/tmp/*'

echo "[customize] done"
