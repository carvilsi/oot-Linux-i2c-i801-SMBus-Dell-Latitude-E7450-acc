#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Rebuild i2c-i801 with the Dell Latitude E7450 no-IRQ quirk for a given kernel.
# Usage: ./build.sh [kernel-release]   (default: running kernel)
set -euo pipefail
cd "$(dirname "$0")"

KVER="${1:-$(uname -r)}"
UPSTREAM="${KVER%%-*}"                  # 7.2.10-arch1-1 -> 7.2.10
UPSTREAM="${UPSTREAM%.arch*}"
URL="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/i2c/busses/i2c-i801.c?h=v${UPSTREAM}"

echo "[*] fetching i2c-i801.c for v${UPSTREAM}"
curl -fsSL -o i2c-i801.c "$URL"
echo "[*] applying patch"
patch -p4 --no-backup-if-mismatch < i2c-i801-e7450-noirq.patch
echo "[*] building against /lib/modules/${KVER}/build"
make KVER="$KVER" >/dev/null
modinfo -F vermagic i2c-i801.ko

cat <<MSG

Install (as root):
  install -Dm644 i2c-i801.ko /lib/modules/${KVER}/updates/i2c-i801.ko
  depmod -a ${KVER}
  modprobe -r dell_lis3lv02d i2c_i801; modprobe i2c_i801
MSG
