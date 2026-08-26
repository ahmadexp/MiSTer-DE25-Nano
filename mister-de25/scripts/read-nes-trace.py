#!/usr/bin/env python3
"""Read the paged DE25 NES execution trace through the HPS GP bridge."""

import mmap
import struct
import time


GP_BASE = 0x20020000
GP_OUT_OFFSET = 0x00
GP_IN_OFFSET = 0x10
RESET_MASK = 0xC0000000
PAGE_MASK = 0x00000007
MAPPER_SELECT = 1 << 27
MASK_SELECT = 1 << 28
BUS_TRACE_SELECT = 1 << 26
BUS_TRACE_INDEX_SHIFT = 23


def read_u32(region, offset):
    return struct.unpack_from("<I", region, offset)[0]


def write_u32(region, offset, value):
    struct.pack_into("<I", region, offset, value)


def read_page(region, base, page):
    write_u32(region, GP_OUT_OFFSET, base | page)
    time.sleep(0.03)
    return (read_u32(region, GP_IN_OFFSET) >> 21) & 0x3F


def read_word(region, base):
    value = 0
    for page in range(6):
        value |= read_page(region, base, page) << (page * 6)
    return value & 0xFFFFFFFF


with open("/dev/mem", "r+b", buffering=0) as device:
    bridge = mmap.mmap(
        device.fileno(),
        0x1000,
        flags=mmap.MAP_SHARED,
        prot=mmap.PROT_READ | mmap.PROT_WRITE,
        offset=GP_BASE,
    )
    original = read_u32(bridge, GP_OUT_OFFSET)
    reset_state = original & RESET_MASK
    if reset_state != 0x80000000:
        bridge.close()
        raise SystemExit(
            f"NES core is not in released reset state 2: GPO=0x{original:08X}"
        )

    try:
        base = reset_state & ~PAGE_MASK
        execution = read_word(bridge, base)
        mapper = read_word(bridge, base | MAPPER_SELECT)
        masks = read_word(bridge, base | MASK_SELECT)
        bus_trace = [
            read_word(
                bridge,
                base | BUS_TRACE_SELECT | (index << BUS_TRACE_INDEX_SHIFT),
            )
            for index in range(8)
        ]
        status = read_page(bridge, base, 6)
        pipeline = read_page(bridge, base, 7)
    finally:
        write_u32(bridge, GP_OUT_OFFSET, original)
        time.sleep(0.03)
        bridge.close()

print(f"GPO original:       0x{original:08X}")
print(f"reset vector:       {(execution >> 8) & 0xFF:02X}{execution & 0xFF:02X}")
print(f"first instruction:  0x{(execution >> 16) & 0xFFFF:04X}")
print(f"mapper flags[31:0]: 0x{mapper:08X}")
print(f"PRG mask:           0x{(masks >> 10) & 0x3FF:03X}")
print(f"CHR mask:           0x{masks & 0x3FF:03X}")
print(
    "trace status:       "
    f"first_pc={(status >> 5) & 1} "
    f"vector_hi={(status >> 4) & 1} "
    f"vector_lo={(status >> 3) & 1} "
    f"ppu_ctrl_write={(status >> 2) & 1} "
    f"ppu_mask_write={(status >> 1) & 1} "
    f"render={status & 1}"
)
print(f"pipeline flags:     {pipeline:06b}")
print("post-vector CPU bus:")
for index, sample in enumerate(bus_trace):
    instrnew = (sample >> 25) & 1
    read = (sample >> 24) & 1
    address = (sample >> 8) & 0xFFFF
    data = sample & 0xFF
    print(
        f"  {index}: addr=0x{address:04X} data=0x{data:02X} "
        f"{'R' if read else 'W'} instrnew={instrnew}"
    )
