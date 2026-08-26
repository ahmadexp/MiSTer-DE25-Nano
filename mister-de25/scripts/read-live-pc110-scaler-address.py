#!/usr/bin/env python3
"""Read the DE25 PC110 scaler's sticky LPDDR read-address telemetry."""

import mmap
import os
import signal
import struct
import time


GP_BASE = 0x20020000
GP_OUT_OFFSET = 0x00
GP_IN_OFFSET = 0x10
SCALER_PHYSICAL_BASE = 0xA0000000
DIAGNOSTIC_MASK = (1 << 25) | (1 << 24) | (3 << 22) | (3 << 20) | 7
SOURCES = ("first", "minimum", "maximum", "last")


def find_main_pid():
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as command_file:
                command = command_file.read().split(b"\0", 1)[0]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if command.endswith(b"/MiSTer"):
            return int(name)
    raise RuntimeError("MiSTer Main process not found")


def read_u32(mapping, offset):
    return struct.unpack_from("<I", mapping, offset)[0]


def write_u32(mapping, offset, value):
    struct.pack_into("<I", mapping, offset, value)


main_pid = find_main_pid()
with open("/dev/mem", "r+b", buffering=0) as device:
    bridge = mmap.mmap(
        device.fileno(),
        0x1000,
        flags=mmap.MAP_SHARED,
        prot=mmap.PROT_READ | mmap.PROT_WRITE,
        offset=GP_BASE,
    )
    original = read_u32(bridge, GP_OUT_OFFSET)
    results = {}
    debug = {}
    responses = []
    flags = 0
    os.kill(main_pid, signal.SIGSTOP)
    try:
        time.sleep(0.05)
        base = original & ~DIAGNOSTIC_MASK
        for source, label in enumerate(SOURCES):
            value = 0
            for page in range(6):
                selector = base | (1 << 24) | (source << 22) | page
                write_u32(bridge, GP_OUT_OFFSET, selector)
                time.sleep(0.02)
                chunk = (read_u32(bridge, GP_IN_OFFSET) >> 21) & 0x3F
                value |= chunk << (page * 6)
            results[label] = value & 0x0FFFFFFF

        write_u32(bridge, GP_OUT_OFFSET, base | (1 << 24) | 6)
        time.sleep(0.02)
        flags = (read_u32(bridge, GP_IN_OFFSET) >> 21) & 0x3F

        for label, extra_selector in (
            ("control", 1 << 21),
            ("position", 1 << 20),
        ):
            value = 0
            for page in range(6):
                selector = (
                    base
                    | (1 << 24)
                    | (3 << 22)
                    | extra_selector
                    | page
                )
                write_u32(bridge, GP_OUT_OFFSET, selector)
                time.sleep(0.02)
                chunk = (read_u32(bridge, GP_IN_OFFSET) >> 21) & 0x3F
                value |= chunk << (page * 6)
            debug[label] = value & 0xFFFFFFFF

        for response_index in range(4):
            response = 0
            for quarter in range(4):
                value = 0
                for page in range(6):
                    selector = (
                        base
                        | (1 << 25)
                        | (1 << 24)
                        | (response_index << 22)
                        | (quarter << 20)
                        | page
                    )
                    write_u32(bridge, GP_OUT_OFFSET, selector)
                    time.sleep(0.02)
                    chunk = (read_u32(bridge, GP_IN_OFFSET) >> 21) & 0x3F
                    value |= chunk << (page * 6)
                response |= (value & 0xFFFFFFFF) << (quarter * 32)
            responses.append(response)
    finally:
        write_u32(bridge, GP_OUT_OFFSET, original)
        time.sleep(0.02)
        os.kill(main_pid, signal.SIGCONT)
        bridge.close()

    framebuffer = mmap.mmap(
        device.fileno(),
        0x1000,
        flags=mmap.MAP_SHARED,
        prot=mmap.PROT_READ,
        offset=SCALER_PHYSICAL_BASE,
    )
    header = bytes(framebuffer[:16])
    expected_responses = bytes(framebuffer[0x100:0x140])
    framebuffer.close()

print(f"Main PID: {main_pid}")
print(f"GPO restored: 0x{original:08X}")
for label in SOURCES:
    value = results[label]
    print(f"{label:7s}: word=0x{value:07X} byte=0x{value << 4:08X}")
span = results["maximum"] - results["minimum"]
print(f"span: {span} 128-bit words ({span << 4} bytes)")
print(
    "flags: "
    f"changed={(flags >> 5) & 1} seen={(flags >> 4) & 1} "
    f"burstcount={flags & 0xF}"
)
control = debug["control"]
position = debug["position"]
print(
    f"control: 0x{control:08X} "
    f"output_input_height={control & 0xFFF} "
    f"detected_input_height={(control >> 12) & 0xFFF} "
    f"read_level={(control >> 24) & 3} "
    f"copy_level={(control >> 26) & 3} "
    f"preload={(control >> 28) & 3} "
    f"vertical_active={(control >> 30) & 1} "
    f"vertical_advance={(control >> 31) & 1}"
)
print(
    f"position: 0x{position:08X} "
    f"output_line={position & 0xFFF} "
    f"source_line={(position >> 12) & 0xFFF} "
    f"read_state={(position >> 24) & 3} "
    f"copy_state={(position >> 26) & 3} "
    f"data_ack={(position >> 28) & 1} "
    f"command_ack={(position >> 29) & 1} "
    f"address_pipe={(position >> 30) & 3}"
)
for index, response in enumerate(responses):
    response_bytes = response.to_bytes(16, "little")
    expected = expected_responses[index * 16 : (index + 1) * 16]
    print(
        f"response{index}: {response_bytes.hex(' ')} "
        f"expected={expected.hex(' ')} match={response_bytes == expected}"
    )
print(f"header: {header.hex(' ')}")
print(
    "image: "
    f"type={header[0]} format={header[1]} "
    f"offset={int.from_bytes(header[2:4], 'big')} "
    f"width={int.from_bytes(header[6:8], 'big')} "
    f"height={int.from_bytes(header[8:10], 'big')} "
    f"stride={int.from_bytes(header[10:12], 'big')}"
)
