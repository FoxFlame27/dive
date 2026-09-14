#!/usr/bin/env bash
# build-iso.sh — build Dive-<version>.iso. Run on a Fedora x86_64 machine or VM (not in a container).
#
#   sudo ./distro/build-iso.sh [releasever]
#
# Produces out/Dive-0.1-x86_64.iso with the volume label DIVE_LIVE (the Windows installer relies on it).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REL="${1:-$(rpm -E %fedora)}"
VER="$(sed -n 's/^DIVE_VERSION="\(.*\)"/\1/p' "$ROOT/distro/dive-setup.sh")"
OUT="$ROOT/out"
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }

dnf install -y lorax-lmc-novirt spin-kickstarts pykickstart anaconda-tui
rm -rf /dive-src && cp -r "$ROOT" /dive-src
ksflatten -c "$ROOT/distro/dive-live.ks" -o /tmp/dive-flat.ks
mkdir -p "$OUT"
setenforce 0 2>/dev/null || true   # livemedia-creator needs this on most hosts
livemedia-creator --make-iso --no-virt \
  --ks /tmp/dive-flat.ks \
  --resultdir "$OUT/lmc" \
  --project Dive --releasever "$REL" \
  --volid DIVE_LIVE \
  --iso-name "Dive-${VER}-x86_64.iso" \
  --iso-only --logfile "$OUT/lmc.log" \
  --tmp /var/tmp
mv "$OUT"/lmc/*.iso "$OUT/" 2>/dev/null || true
ls -lh "$OUT"/*.iso
# Sanity: the live squashfs must stay under 4 GB (FAT32 limit) for install-from-Windows.
echo "Check: LiveOS/squashfs.img must be < 4 GB. Publish the ISO and point installer/windows/install.ps1 at it."
