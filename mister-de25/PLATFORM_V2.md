# DE25 MiSTer platform v2

## Purpose

Platform v2 is the clean common boundary for a full MiSTer port to the
DE25-Nano. The Menu is the first persona because it exercises HPS boot,
runtime RBF loading, DDR, SDRAM pins, HDMI, OSD, USB input, and the standard
MiSTer `HPS_BUS` without adding a console core's own failure modes.

The known-good platform-v1 artifacts remain untouched. V2 has its own Quartus
revision and artifact directory so recovery never depends on an experimental
clock profile.

## Platform ABI

Platform v2 deliberately uses the complete bridge-enabled HPS I/O
compatibility ABI. Its hash is:

```text
FDCDD4C99876BAE3D17BB5B0AF4A4C7B7D55B2CE17D05C535A5BF69DD7DE930B
```

The hash is stored in `platforms/fdcd.hps-io-hash`. It is produced by the
current Quartus Pro 25.3.1 generated HPS subsystem, including the HPS-to-fabric
reset fanout and video-buffer bridge. The earlier `078A...` ABI remains the
recovery platform and is not silently mixed with v2 images.

An earlier provisional C600 build omitted part of this full bridge boundary.
The clean bootstrap guard rejected it when the generated HPS configuration and
the manifest disagreed. FDCD is the already reproduced ABI used by the full
video-buffer bridge and is therefore the v2 foundation.

The first clean Menu-v2 build exports the HPS hierarchy as a synthesized
design-partition database:

```text
artifacts/menu-v2/de25_mister_hps_fdcd_synth.qdb
```

Every later v2 core imports this exact partition and must embed the FDCD hash.
The synthesized snapshot fixes the generated HPS netlist and I/O contract, but
still lets Quartus place and route each complete core as one coherent image.
This avoids the fitter consistency failure seen when a final routed HPS
partition is imported into a different persona.

## Architecture contract

### Recovery and infrastructure clocks

`CLOCK0_50` is the always-on reference for HPS bridges, DDR access, HDMI
initialization, the audio clock PLL, and the fixed scaler output. Those paths
must remain operational even if an external clock profile is absent or bad.

The Si5332B outputs on `CLOCK1_50` and `CLOCK2_50` are persona clock sources.
A persona may use them only after the platform service reports both a valid
device identity and live measured outputs. A failed external clock must hold
that persona in reset without taking down HPS recovery.

### Si5332B control plane

The U24 `SDA` and `SCL` pads are wired to GPIO 1 (JP2) physical pins 1 and 2:

| Signal | FPGA port | Agilex pin |
| --- | --- | --- |
| SDA | `SI5332_SDA` | `BV14` |
| SCL | `SI5332_SCL` | `CG26` |

Both pins are driven strictly open drain. The baseline performs these
read-only operations:

1. Probe addresses `0x6a` and `0x6b`.
2. Read device part, revision, grade, factory OPN, design ID, configured I2C
   address, supply status, and operational state.
3. Measure both FPGA-visible Si5332 outputs against `CLOCK0_50`.

Volatile writes are physically disabled in the Menu baseline. Skyworks
requires the complete ordered ClockBuilder Pro export, including preamble and
postamble, generated for the exact detected GM variant. A core profile must
meet that requirement before its write stream is enabled.

### Reset sequencing

Every clock domain uses asynchronous assertion and synchronous release. HPS
warm reset acknowledgement remains independent of a persona clock. Native
SDRAM is quiesced before reconfiguration, and a persona stays reset until all
of its selected clock sources report ready.

### Video and OSD

Low-resolution and asynchronous core video is frame-buffered into LPDDR4 and
scaled to a fixed 640x480 HDMI mode. The MiSTer OSD is composited after the
scaler so its 512-column, 16-row bitmap is neither aliased nor clipped. The
final RGB, DE, HS, and VS signals are registered together before the ADV7513.

### Audio

The shared transmitter emits standard 16-bit stereo I2S:

| Signal | Nominal rate |
| --- | --- |
| MCLK | 24.576 MHz |
| BCLK | 1.536 MHz |
| LRCLK | 48 kHz |

Core samples cross into the audio domain through stable double sampling. The
ADV7513 enables only I2S stream 0, declares two channels, and uses a 16-bit
word length. This replaces the prior 96 kHz framing mismatch and enabled but
unwired I2S inputs that caused continuous crackling.

### Core interface

Each ported core remains an upstream-compatible `emu` module. The platform
owns HPS, DDR, SDRAM arbitration, reset, OSD, video scaling, HDMI, audio, and
clock selection. A persona supplies only its native clocks, video, audio,
memory requests, and standard MiSTer control ports. Complete runtime RBFs are
used, not partial reconfiguration.

The common Quartus overlay is `quartus/de25_platform_v2.qsf`. A new persona
sources its existing DE25 core QSF first and this overlay second. This keeps
the board pins and services in one reviewed file while preserving each core's
upstream source list and native timing constraints.

## Build and validation

Run the fast platform tests:

```sh
mister-de25/scripts/test-platform-v2.sh
```

Build the independent Menu-v2 revision:

```sh
mister-de25/scripts/build-menu-v2.sh
```

This command is the platform bootstrap. It regenerates the current HPS IP,
performs a clean compile, exports the reusable synthesized HPS partition, and
rejects the result unless the embedded HPS I/O hash is exactly FDCD.

The runtime artifact is written to:

```text
mister-de25/artifacts/menu-v2/menu_v2.rbf
```

The matching HPS-first QSPI image is written to:

```text
mister-de25/artifacts/menu-v2/DE25_MISTER_MENU_V2_HPS_FIRST.hps.jic
```

After the bootstrap succeeds, build a registered core against the same ABI by
exporting these variables before its existing build script:

```sh
export DE25_HPS_PARTITION_MODE=reuse
export DE25_HPS_PARTITION_QDB="$PWD/mister-de25/artifacts/menu-v2/de25_mister_hps_fdcd_synth.qdb"
export DE25_EXPECTED_HPS_IO_HASH_FILE="$PWD/mister-de25/platforms/fdcd.hps-io-hash"
mister-de25/scripts/build-catalog.sh --core NES
```

NES is the first concrete persona revision using the complete overlay and the
reused HPS partition:

```sh
mister-de25/scripts/build-nes-v2.sh
```

Its QSF is intentionally small: it sources the existing NES port and then the
common Platform V2 overlay. Later cores should follow that same pattern.

The first complete NES-v2 validation produced `artifacts/nes-v2/NES_v2.rbf`
with the FDCD ABI. Quartus reported 0 violated setup paths, 0 violated hold
paths, +0.654 ns worst setup slack, and positive external SDRAM setup and hold
margins. Its SHA-256 is:

```text
84036c6ae7e346e6a1e7730022d17035cf808c68b5796bf596838dc29c3240e1
```

Three additional personas now build against the same synthesized FDCD HPS
partition:

| Persona | Build command | Runtime artifact | Worst setup | Worst hold | SHA-256 |
| --- | --- | --- | ---: | ---: | --- |
| IBM PC/XT | `scripts/build-pcxt-v2.sh` | `artifacts/pcxt-v2/PCXT_v2.rbf` | +0.245 ns | +0.000 ns | `a20268c5bd3ad04c36fca4c88b965a073cc1644f84124c918e0c2c494c5d32b6` |
| Sega Master System / Game Gear | `scripts/build-sms-v2.sh` | `artifacts/sms-v2/SMS_v2.rbf` | +0.893 ns | +0.000 ns | `09e7c277addd60a6d300ccb863f66dff35c343b52222a070e17e155a422c70a2` |
| ao486 | `scripts/build-ao486-v2.sh` | `artifacts/ao486-v2/AO486_v2.rbf` | +0.337 ns | +0.000 ns | `c56757c5109359c46ae484a8de74bed513dde8ced5bfc891277b0518a2feb6ca` |

All three have zero setup and hold violations and embed the exact FDCD HPS
I/O hash. The SMS persona contains both Master System and Game Gear modes.
ao486 uses the supported IOSSM Calibration IP path for runtime CPU-clock
selection, the shared platform video clock, and deterministic fabric clocks
for its UART and MPU interfaces. Its GUS native-SDRAM path uses a second,
related PLL output for the physical SDRAM clock, frequency-aware refresh
scheduling, and timing-checked bidirectional data I/O. The main ao486
DDR-backed PC memory path is also included. Real GUS playback remains pending
on-board validation. The upstream 15 MHz GF1 mode remains unsupported; use a
30, 56.25, 90, or 100 MHz ao486 clock profile when validating GUS.

Five additional console personas completed the same build and timing gates:

| Persona | Build command | Runtime artifact | Worst setup | ALMs | SHA-256 |
| --- | --- | --- | ---: | ---: | --- |
| Atari 7800 / 2600 | `scripts/build-atari7800-v2.sh` | `artifacts/atari7800-v2/Atari7800_v2.rbf` | +0.551 ns | 59% | `6013be37c79c8d924405b6f2bbd459c98eaf4bedd4e83f901ef81eeb0799ea7f` |
| Atari Jaguar | `scripts/build-jaguar-v2.sh` | `artifacts/jaguar-v2/Jaguar_v2.rbf` | +0.070 ns | 74% | `aebd924e5d4e0832d1b5588bd6191b9a6dfbe66e7d90e5528475e1b959a6efcc` |
| PlayStation | `scripts/build-psx-v2.sh` | `artifacts/psx-v2/PSX_v2_ntsc_bringup.rbf` | +0.477 ns | 95% | `09630e3f1f858b2ea2465cba1b9ac5e26bfed1a236521d07a8f8291848f80aad` |
| Nintendo 64 | `scripts/build-n64-v2.sh` | `artifacts/n64-v2/N64_v2_ntsc_bringup.rbf` | +0.859 ns | 93% | `ffb8d80374def7b4fa82daf3bc9602ed16bedda9cbd181232fd260c0128cf60d` |
| Sega Saturn | `scripts/build-saturn-v2.sh` | `artifacts/saturn-v2/Saturn_v2_ntsc_light_bringup.rbf` | +0.051 ns | 97% | `6cce06085296b1aa6b6bbc99dc33d846b914c59df3c0c3fdefed70a2db1a5406` |

Each report has zero failing setup and hold endpoints and zero unconstrained
endpoints. Their complete RBFs preserve the FDCD HPS I/O hash. Atari 7800,
Jaguar, and PlayStation have passed the guarded runtime loader on the physical
DE25-Nano and recovered to the unchanged Menu. Nintendo 64 and Saturn have not
yet been loaded on hardware. BIOS, cartridge, controller, video, and audio
tests remain separate hardware-validation gates for all five personas. Jaguar
and Saturn have positive but narrow setup margin, so their first content tests
must keep automatic Menu recovery enabled.

All runtime RBFs remain complete FPGA images. The partition is a build-time ABI
mechanism, not partial reconfiguration.

The build is accepted only after synthesis, fit, assembly, static timing,
SDRAM timing reports, HPS-first packaging, HPS I/O hash verification, and
artifact digest generation all pass.

The first hardware transition from recovery ABI 078A to platform-v2 ABI FDCD
must be coordinated: install the matching Menu RBF and userspace files, program
the matching HPS-first QSPI JIC, and perform one real board power cycle. The
migration guard intentionally prevents an old QSPI HPS configuration from
loading an FDCD runtime image, or the reverse. A remote FPGA reset is not a
substitute for that first power cycle.

After loading Menu v2, stop MiSTer Main temporarily and read the complete
clock-service status through JTAG:

```sh
system-console --script=mister-de25/scripts/read-platform-v2-status.tcl \
  mister-de25/quartus/output_files_menu_v2/DE25_MISTER_MENU_V2.sof
```

## Porting sequence

1. Build and preserve the FDCD Menu, HPS partition, RBF, and QSPI artifacts.
2. Perform the coordinated 078A-to-FDCD migration and one physical power cycle.
3. Boot and remotely verify Menu v2, HDMI, OSD geometry, and silent audio.
4. Read and record the installed Si5332 identity and current output rates.
5. Generate and verify exact ClockBuilder Pro profiles for representative
   fractional clocks, with automatic internal-clock fallback.
6. Verify NES, PCXT, SMS/Game Gear, and ao486 on hardware, including ROM or
   disk loading, OSD, video, input, and audio.
7. Move PC110 and the remaining catalog cores to the same boundary.
8. Automate per-core clock-profile metadata, build matrix validation, runtime
   selection, recovery, and updater packaging.
# Parallel Quartus builds

Large personas can be built concurrently on a multi-socket build server, but
every container must bind-mount a separate workspace. Quartus IP generation
updates project-local HPS and Qsys files, so multiple containers must never
write to the same checkout.

Use a separate `QUARTUS_HOME_DIR` for each workspace. The generic persona
builder also accepts these optional Docker controls:

```text
DE25_DOCKER_NAME=quartus-psx
DE25_DOCKER_CPUS=96
DE25_DOCKER_CPUSET_CPUS=0-63,128-191
DE25_DOCKER_CPUSET_MEMS=0
DE25_DOCKER_MEMORY=128g
QUARTUS_HOME_DIR=/home/user/quartus-pro-home-psx
```

For a 256-thread, 503 GiB host, three concurrent large-core builds at roughly
80 CPUs and 128 GiB each leave capacity for the operating system and serial IP
generation phases. On a dual EPYC 7713 host, CPUs `0-63,128-191` belong to
NUMA node 0 and CPUs `64-127,192-255` belong to NUMA node 1. Pin concurrent
large builds to different nodes when practical. Small cores can use lower
limits.
