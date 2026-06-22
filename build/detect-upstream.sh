#!/usr/bin/env bash
# Prints the latest upstream Alpine cloud-image version on stdout (single line).
#
# Alpine publishes versioned cloud images at
#   https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/
# with filenames `generic_alpine-X.Y.Z-x86_64-{bios,uefi}-cloudinit-r0.qcow2`.
# (Upstream renamed the prefix from `nocloud_` to `generic_` around the
# 3.24 cycle — the directory also carries `*-tiny-*` and `*-metal-*`
# flavors we deliberately ignore; we track the plain `cloudinit-r0`.)
# `latest-stable` redirects to the current stable branch (e.g. v3.23) but the
# directory contains every minor release built for that branch — we pick the
# highest semver match on the BIOS variant (UEFI follows the same version).
#
# Format: X.Y.Z (semver). Git tag: v<VERSION>.
#
# Runs in the upstream-watch reusable workflow (no KVM needed) — keep it
# portable bash + curl + GNU sort/grep only.

set -euo pipefail

URL='https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/'

listing=$(curl -fsL "$URL")
if [[ -z "$listing" ]]; then
  echo "::error::could not fetch directory listing from $URL" >&2
  exit 1
fi

# Extract every X.Y.Z that appears in `generic_alpine-<v>-x86_64-bios-cloudinit-r0.qcow2`,
# sort by semver, return the highest. -V handles dotted-numeric correctly.
# The `-r0\.qcow2` anchor keeps us off the `cloudinit-metal-r0` flavor.
version=$(printf '%s\n' "$listing" \
  | grep -oE 'generic_alpine-[0-9]+\.[0-9]+\.[0-9]+-x86_64-bios-cloudinit-r0\.qcow2' \
  | sed -E 's/^generic_alpine-([0-9]+\.[0-9]+\.[0-9]+).*/\1/' \
  | sort -uV \
  | tail -n1)

if [[ -z "$version" ]]; then
  echo "::error::no generic_alpine-X.Y.Z-x86_64-bios-cloudinit-r0.qcow2 entries in $URL" >&2
  exit 1
fi

printf '%s\n' "$version"
