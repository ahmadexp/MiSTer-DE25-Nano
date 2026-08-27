# IBM PC110 core

This directory contains the supplemental IBM Palm Top PC 110 core used by the
DE25-Nano platform. It is one ported core within the wider MiSTer-DE25-Nano
project and is deliberately separated from the repository root and shared
platform code.

The implementation combines the ao486 CPU and PC-compatible devices with the
PC110 chipset, memory map, flash layout, PCMCIA registers, Japanese font-ROM
banking, and machine-specific storage profile. Hardware testing has reached
the IBM BIOS, Easy-Setup, PC DOS J7.0/V, and PersonaWare.

## Layout

- `PC110.sv`: MiSTer core top level.
- `rtl/`: ao486, PC-compatible peripheral, and PC110 chipset RTL.
- `PC110.qpf`, `PC110.qsf`, and `PC110.sdc`: retained Cyclone V project.
- `de25-nano/` at the repository root: early Agilex board diagnostics and
  bring-up projects shared with the platform history.
- `mister-de25/` at the repository root: current Platform V2 integration and
  the production DE25 PC110 build.

## DE25-Nano build

From the repository root, fetch the pinned upstream sources and run:

```sh
mister-de25/scripts/build-pc110.sh
```

The build uses `mister-de25/quartus/DE25_MISTER_PC110.qsf`, the common Agilex
board shell, and this directory's PC110 sources. Candidate status and timing
are tracked in
[`mister-de25/CORE_CANDIDATE_STATUS.md`](../../mister-de25/CORE_CANDIDATE_STATUS.md).

## Firmware and disks

No IBM BIOS, font ROM, operating-system image, or disk image is included.
Users must provide legally obtained firmware and media. PC110-compatible raw
VHDs may use a same-basename geometry file, for example:

```ini
HEADS = 2
SECTORS = 32
CYLINDERS = 128
```

## License

The ao486 sources retain their upstream BSD terms. MiSTer framework sources
and PC110-specific files retain their applicable upstream and GPL notices.
See [`LICENSE`](../../LICENSE),
[`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md), and the per-file
headers. No IBM firmware is included.
