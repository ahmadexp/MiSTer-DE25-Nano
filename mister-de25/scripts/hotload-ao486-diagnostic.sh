#!/usr/bin/env bash
set -euo pipefail

image=${1:-/media/fat/_Computer/AO486_20260819_DIAG.rbf}
unit=${2:-mister-ao486-diag.service}

systemctl stop mister-ao486-final.service 2>/dev/null || true
systemctl stop mister-ao486-diag.service 2>/dev/null || true
systemctl stop mister-ao486-reset-level-diag.service 2>/dev/null || true
systemctl stop mister-ao486-reset-decl-diag.service 2>/dev/null || true
systemctl stop mister-ao486-vga-diag.service 2>/dev/null || true
systemctl stop "$unit" 2>/dev/null || true

# Match Main's persona-load handshake. Keeping GPO in the live state while the
# core-side DDR master is replaced can let the new core issue traffic before
# the FPGA manager has finished isolation and leave the HPS transaction hung.
python3 - <<'PY'
import mmap
import struct

with open("/dev/mem", "r+b", buffering=0) as device:
    bridge = mmap.mmap(
        device.fileno(),
        0x00400000,
        flags=mmap.MAP_SHARED,
        prot=mmap.PROT_READ | mmap.PROT_WRITE,
        offset=0x20000000,
    )
    struct.pack_into("<I", bridge, 0x00020000, 0x40000000)
    bridge.close()
PY
/usr/libexec/mister-de25-load "$image"
printf '%s\n' "$image" >/run/mister-de25-selected-core
systemd-run --unit="${unit%.service}" \
    --property=WorkingDirectory=/media/fat \
    --property=Restart=no --collect /media/fat/MiSTer
