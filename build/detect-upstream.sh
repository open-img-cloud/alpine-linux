#!/usr/bin/env bash
# Prints the latest upstream Alpine cloud-image version on stdout (single line).
#
# Alpine publishes versioned cloud images at
#   https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/
# with filenames `nocloud_alpine-X.Y.Z-x86_64-{bios,uefi}-cloudinit-r0.qcow2`.
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

# Extract every X.Y.Z that appears in `nocloud_alpine-<v>-x86_64-bios-cloudinit-r0.qcow2`,
# sort by semver, return the highest. -V handles dotted-numeric correctly.
version=$(printf '%s\n' "$listing" \
  | grep -oE 'nocloud_alpine-[0-9]+\.[0-9]+\.[0-9]+-x86_64-bios-cloudinit-r0\.qcow2' \
  | sed -E 's/^nocloud_alpine-([0-9]+\.[0-9]+\.[0-9]+).*/\1/' \
  | sort -uV \
  | tail -n1)

if [[ -z "$version" ]]; then
  echo "::error::no nocloud_alpine-X.Y.Z-x86_64-bios-cloudinit-r0.qcow2 entries in $URL" >&2
  exit 1
fi

printf '%s\n' "$version"
