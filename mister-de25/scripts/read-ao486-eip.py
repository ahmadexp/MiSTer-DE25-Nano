#!/usr/bin/env python3
"""Read the paged ao486 EIP diagnostic through the DE25 HPS GP bridge."""

import mmap
import struct
import time


GP_BASE = 0x20020000
GP_OUT_OFFSET = 0x00
GP_IN_OFFSET = 0x10


with open("/dev/mem", "r+b", buffering=0) as device:
    bridge = mmap.mmap(
        device.fileno(),
        0x1000,
        flags=mmap.MAP_SHARED,
        prot=mmap.PROT_READ | mmap.PROT_WRITE,
        offset=GP_BASE,
    )
    original = struct.unpack_from("<I", bridge, GP_OUT_OFFSET)[0]
    try:
        for sample in range(8):
            chunks = []
            for page in range(6):
                struct.pack_into("<I", bridge, GP_OUT_OFFSET, 0x80000000 | page)
                time.sleep(0.01)
                gp_in = struct.unpack_from("<I", bridge, GP_IN_OFFSET)[0]
                chunks.append((gp_in >> 21) & 0x3F)
            linear = sum(chunk << (6 * page) for page, chunk in enumerate(chunks))
            print(f"sample={sample} chunks={chunks} linear=0x{linear:08X}")
            time.sleep(0.05)
    finally:
        struct.pack_into("<I", bridge, GP_OUT_OFFSET, original)
        bridge.close()
