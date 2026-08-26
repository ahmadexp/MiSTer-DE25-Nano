#!/usr/bin/env python3
"""Read the DE25 MiSTer GP input register through the HPS bridge."""

import mmap
import struct
import time


GP_BASE = 0x20020000
GP_OUT_OFFSET = 0x00
GP_IN_OFFSET = 0x10


with open("/dev/mem", "rb", buffering=0) as device:
    bridge = mmap.mmap(
        device.fileno(),
        0x1000,
        flags=mmap.MAP_SHARED,
        prot=mmap.PROT_READ,
        offset=GP_BASE,
    )
    for _ in range(8):
        gp_out = struct.unpack_from("<I", bridge, GP_OUT_OFFSET)[0]
        gp_in = struct.unpack_from("<I", bridge, GP_IN_OFFSET)[0]
        print(
            f"GPO=0x{gp_out:08X} GPI=0x{gp_in:08X} "
            f"reset={(gp_out >> 30) & 0x3} diag={(gp_in >> 21) & 0x3f}"
        )
        time.sleep(0.2)
    bridge.close()
