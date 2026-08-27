# MiSTer platform port for the DE25-Nano

This repository contains an independent MiSTer platform port for the Terasic
DE25-Nano and its Agilex 5 A5EB013 FPGA. It provides the shared Platform V2
board shell, Menu port, core compatibility patches, build automation, runtime
loader, SD-card tooling, hardware documentation, and a growing catalog of
ported MiSTer cores.

This is active bring-up work, not an official MiSTer distribution. A successful
Quartus build or guarded FPGA load does not by itself establish complete game,
BIOS, controller, video-mode, or audio compatibility.

## Current core status

| Core | Build and timing | Hardware gate |
| --- | --- | --- |
| Menu V2 | pass | boots on DE25-Nano |
| Apple I | pass | packaged |
| Atari 7800 / 2600 | pass | guarded load passed |
| ao486 | pass | content test pending |
| IBM PC/XT | pass | content test pending |
| IBM PC110 | pass | Personaware boots; corrected scaler active |
| Atari Jaguar | pass | guarded load passed; content pending |
| Minimig | pass | packaged |
| Nintendo 64 | pass | hardware load pending |
| NES | pass | packaged |
| PlayStation | pass | guarded load passed; BIOS/content pending |
| Sega Master System / Game Gear | pass | content test pending |
| Sega Saturn LIGHT | pass | hardware load pending |
| SNES | pass | packaged |
| TurboGrafx-16 | pass | packaged |

The exact candidate status, resource use, timing margins, and artifact hashes
are recorded in [`mister-de25/CORE_CANDIDATE_STATUS.md`](mister-de25/CORE_CANDIDATE_STATUS.md).

## Repository layout

- `mister-de25/`: Platform V2, Quartus projects, core patches, build scripts,
  Linux runtime integration, SD-card tooling, and tests.
- `hardware/de25-nano-bridge/`: KiCad source, reference Gerbers, and installation
  documentation for the passive GPIO 1 to Si5332B I2C bridge.
- `de25-nano/`: low-level board bring-up, Terasic GHRD import, and Si5332
  diagnostic projects.
- `shared/mister/`: shared upstream MiSTer framework sources needed by bundled
  platform integrations.

All core repositories, including IBM PC110, are fetched at pinned identities
during the build flow and patched locally when necessary. Generated upstream
checkouts, Quartus databases, ROMs, disk images, and private cartridge content
are intentionally excluded from version control.

## Platform V2

Platform V2 standardizes the DE25-Nano boundary used by Menu and all ported
cores:

- an immutable Terasic HPS partition reused across personas;
- the FDCD HPS I/O compatibility identity;
- common HPS DDR, native SDRAM, HDMI, audio, input, and runtime-loader wiring;
- exact Agilex 5 PLL projects and static timing constraints;
- guarded loading with automatic recovery to Menu;
- read-only Si5332 detection and clock monitoring.

Si5332 programming remains disabled until board-specific profiles and rollback
behavior are validated. Cores currently use their checked Agilex PLL paths.

See [`mister-de25/PLATFORM_V2.md`](mister-de25/PLATFORM_V2.md) and
[`mister-de25/SI5332B.md`](mister-de25/SI5332B.md) for the design details.

The optional passive bridge PCB makes the otherwise unconnected U24 SDA and
SCL pads available to the FPGA through GPIO 1 pins 1 and 2. Its source and
verified electrical mapping are documented in
[`hardware/de25-nano-bridge/README.md`](hardware/de25-nano-bridge/README.md).

## Building

Quartus Prime Pro 25.3.1 with Agilex 5 device support is the validated toolchain.
The build scripts can use a native installation or the configured Quartus
container image.

Prepare the licensed Terasic rev-B GHRD and the exact upstream source revisions
before the first build:

```sh
de25-nano/scripts/import-terasic-ghrd.sh /path/to/DE25-Nano_revB_v.1.0.0_ResourcePackage.zip
mister-de25/scripts/fetch-main-mister.sh
mister-de25/scripts/fetch-core-catalog.sh
```

The fetch scripts refuse to overwrite modified checkouts. Upstream trees are
kept under the ignored `mister-de25/upstream/` directory and the DE25 changes
remain reviewable as patch series in this repository.

```sh
mister-de25/scripts/test.sh
mister-de25/scripts/build-menu-v2.sh
mister-de25/scripts/build-nes-v2.sh
mister-de25/scripts/build-pcxt-v2.sh
mister-de25/scripts/build-sms-v2.sh
mister-de25/scripts/build-ao486-v2.sh
```

Large-core entry points are:

```sh
mister-de25/scripts/build-atari7800-v2.sh
mister-de25/scripts/build-jaguar-v2.sh
mister-de25/scripts/build-psx-v2.sh
mister-de25/scripts/build-n64-v2.sh
mister-de25/scripts/build-saturn-v2.sh
```

Every release build must pass synthesis, fitting, assembly, static timing,
SDRAM I/O timing, HPS I/O hash validation, and RBF digest generation.

## Installing

Verified candidate bundles are published under GitHub Releases. The updater
stages and verifies the complete bundle before changing the target and retains
the previous installation for rollback.

On an already migrated FDCD system:

```sh
sudo /media/fat/Scripts/update_de25.sh /path/to/extracted-update-bundle
sudo reboot
```

The first migration from another HPS I/O identity requires the matching
HPS-first QSPI image and a physical power cycle. Do not bypass the compatibility
interlock.

## Licensing

The repository license is in [`LICENSE`](LICENSE). Upstream projects retain
their own licenses and copyright notices. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and the source repositories
recorded in `mister-de25/official-core-catalog.tsv`.
