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

# NOTE: Alpine isn't always recognised by libguestfs OS inspection for
# `--install` — use `--run-command 'apk add ...'` to be safe across
# upstream image revisions.
virt-customize -a "$QCOW2" \
  --run-command 'apk update' \
  --run-command 'apk upgrade' \
  --run-command 'apk add qemu-guest-agent' \
  --copy-in "${CONFIG_DIR}/cloud.cfg:/etc/cloud/" \
  --copy-in "${CONFIG_DIR}/grub:/etc/default/" \
  --mkdir /usr/local/sbin \
  --copy-in "${CONFIG_DIR}/serial-config.sh:/usr/local/sbin/" \
  --run-command 'chmod +x /usr/local/sbin/serial-config.sh && /usr/local/sbin/serial-config.sh' \
  --run-command 'if command -v grub-mkconfig >/dev/null 2>&1; then grub-mkconfig -o /boot/grub/grub.cfg; fi' \
  --run-command 'rc-update add qemu-guest-agent default' \
  --run-command 'rm -rf /var/cache/apk/* /tmp/* /var/tmp/*'

echo "[customize] done"
