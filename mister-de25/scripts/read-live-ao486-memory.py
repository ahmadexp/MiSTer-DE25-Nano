#!/usr/bin/env python3
"""Read selected ao486 locations from the DE25 LPDDR window."""

import mmap
import struct


BASE = 0xB0000000
SIZE = 0x100000
REGIONS = (
    ("LOW_RAM", 0x00000, 64),
    ("BDA", 0x00400, 64),
    ("BDA_VIDEO", 0x00440, 64),
    ("BDA_TIMER", 0x00460, 32),
    ("TEXT_RAM", 0xB8000, 64),
    ("VGA_BIOS", 0xC0000, 64),
    ("BIOS", 0xF0000, 64),
)


with open("/dev/mem", "rb", buffering=0) as device:
    memory = mmap.mmap(
        device.fileno(),
        SIZE,
        flags=mmap.MAP_SHARED,
        prot=mmap.PROT_READ,
        offset=BASE,
    )
    for label, offset, size in REGIONS:
        data = memory[offset : offset + size]
        words = struct.unpack(f"<{size // 4}I", data)
        print(f"{label} @ 0x{BASE + offset:08X}")
        for index in range(0, len(words), 4):
            chunk = " ".join(f"{value:08X}" for value in words[index : index + 4])
            print(f"  +0x{index * 4:02X} {chunk}")
    memory.close()
