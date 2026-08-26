#!/usr/bin/env python3
"""Assert and release the DE25 MiSTer core reset through the HPS GP bridge."""

import argparse
import mmap
import struct
import time


GP_BASE = 0x20020000
GP_RESET_MASK = 0xC0000000
GP_RESET_ASSERT = 0x40000000
GP_RESET_RELEASE = 0x80000000
AO486_RAM_BASE = 0xB0000000


parser = argparse.ArgumentParser()
parser.add_argument(
    "--clear-bda",
    action="store_true",
    help="clear ao486 physical 0x400..0x4ff while reset is asserted",
)
args = parser.parse_args()


with open("/dev/mem", "r+b", buffering=0) as device:
    bridge = mmap.mmap(
        device.fileno(),
        0x1000,
        flags=mmap.MAP_SHARED,
        prot=mmap.PROT_READ | mmap.PROT_WRITE,
        offset=GP_BASE,
    )
    current = struct.unpack_from("<I", bridge, 0)[0]
    payload = current & ~GP_RESET_MASK
    asserted = payload | GP_RESET_ASSERT
    released = payload | GP_RESET_RELEASE
    struct.pack_into("<I", bridge, 0, asserted)
    time.sleep(0.1)
    if args.clear_bda:
        memory = mmap.mmap(
            device.fileno(),
            0x1000,
            flags=mmap.MAP_SHARED,
            prot=mmap.PROT_READ | mmap.PROT_WRITE,
            offset=AO486_RAM_BASE,
        )
        memory[0x400:0x500] = bytes(0x100)
        memory.close()
    time.sleep(0.1)
    struct.pack_into("<I", bridge, 0, released)
    observed = struct.unpack_from("<I", bridge, 0)[0]
    bridge.close()

print(f"GPO reset pulse: 0x{asserted:08X} -> 0x{observed:08X}")
