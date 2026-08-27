# MiSTer platform port for DE25-Nano

This directory contains the platform-level work needed to run the MiSTer
framework on the Terasic DE25-Nano Agilex 5 SoC board. It is separate from the
PC110-specific target in `de25-nano/`.

## Compatibility strategy

The port preserves the interfaces seen by a normal MiSTer core:

- the standard `emu` top-level contract;
- the 46-bit `HPS_BUS` and `hps_io` command protocol;
- the 128 MB, 16-bit FPGA SDRAM interface;
- the `DDRAM_*` access path to HPS memory;
- MiSTer video, audio, input, image, and OSD conventions.

Existing Cyclone V `.rbf` files cannot configure an Agilex 5 device. Every
core must be synthesized, fitted, timed, and packaged for the DE25-Nano. The
goal is to reuse the emulation HDL and apply a common platform overlay, rather
than maintain a hand-written fork of every core.

The production architecture switches complete HPS-first Agilex RBFs. Every
image compiles the same source-level board shell together with one core, and
every image must preserve the installed HPS I/O hash. This is not partial
reconfiguration: the ARM keeps running while Linux's FPGA manager replaces
the fabric image. An evaluated Reserved Core QDB could not route the clock
domains required by the supported cores on this device, while complete images
fit and time cleanly and let Quartus place each core's IOPLLs legally.

The DE25-Nano has the same capacity of native low-latency SDRAM expected by
MiSTer: 128 MB on a 16-bit bus. This memory is already soldered to the board as
two 64 MB devices. No external MiSTer SDRAM module is required, and one must
not be attached to GPIO0 or GPIO1 for this port. The SDRAM pinout differs, but
a normal core's signals pass through the platform shell without translating
the memory protocol. HPS-side DDRAM is backed by the board's 1 GB LPDDR4. The shell and
ARM runtime translate MiSTer's logical `0x20000000` through `0x3fffffff` DDR
window to physical `0xa0000000` through `0xbfffffff`. The supplied device-tree
overlay reserves that complete 512 MiB window from Linux allocation while
retaining its normal ARM64 memory mapping, which Main requires for safe bulk
ROM and RAM transfers through `/dev/mem`.
Main's logical `0x1ffff000` core-switch handoff page is translated to physical
`0x9ffff000` and reserved separately.

## What can and cannot be reused

| Component | Reuse strategy |
| --- | --- |
| Existing DE10-Nano `.rbf` files | Cannot be reused; they contain Cyclone V device configuration. |
| Core emulation HDL | Reuse upstream wherever it is portable. |
| Standard `emu` and `hps_io` interfaces | Preserve in the DE25 shell. |
| Cyclone V `sys_top`, HPS atoms, PLLs, and constraints | Replace once with Agilex 5 platform equivalents. |
| Core-specific PLLs and vendor RAM blocks | Regenerate or patch per core when synthesis requires it. |
| Main_MiSTer ARMv7 executable | Rebuild for AArch64 and use the Linux FPGA-region/configfs backend. |
| Menu, updater, filters, scripts, and data layout | Preserve behavior and package DE25-specific binaries. |

This means every supported core goes through synthesis, fitting, timing, and
bitstream packaging, but it does not mean rewriting every core. The automated
pipeline applies the common shell first and records only genuine per-core
exceptions.

## Agilex 5 variable PLL support

Agilex 5 support first appeared in Quartus Prime Pro 24.1. The official I/O PLL
dynamic-reconfiguration flow was added in 24.2, so cores that change clocks at
run time require Quartus 24.2 or newer. The DE25 build currently uses 25.3.1.

The board's production `A5EB013BB23BE4SCS` device exposes the direct HVIO IOPLL
Avalon reconfiguration interface. A trial synthesizes that interface, but the
fitter cannot connect it to this package's `P2X_CORE_ITERM`. The implemented
route therefore uses the documented EMIF Calibration IP AXI-Lite bridge. It
completes synthesis, fitting, assembly, and timing analysis for the exact board
OPN in Quartus Pro 25.3.1. `scripts/fix-emif-calibration-ip.sh` repairs a
reproducible omission in the standalone generated Calibration IP before the
build stages run.

Quartus 25.3 does contain a real device-revision restriction: its Ethernet IP
rejects the HVIO IOPLL on `MAIN_SM7_REVA` OPNs. This is not the DE25-Nano die.
Querying the exact `A5EB013BB23BE4SCS` OPN through Quartus system metadata gives
`MAIN_SM4` and `MAIN_SM4_REVB`. `scripts/check-iopll-reconfig.sh` verifies both
the die eligibility and the required reconfiguration interface before use.

Cyclone V's `pll_cfg` register protocol is not compatible with that interface.
Variable-clock cores therefore use an Agilex-specific controller that performs
the documented byte transfers, read-modify-write operations, PLL reset pulse,
and explicit recalibration. The controller follows the HSIO I/O PLL sequence:
enable register access at `0x10`, clear status at `0x58`, update M, charge-pump,
and C counters, pulse reset at `0x80[2]`, request recalibration at `0x88[11]`,
then wait for a real unlock/relock transition. Register `0x48[14]` is not part
of this sequence. It is the recalibration-enable operation documented only for
HVIO PLLs and must not be sent to this HSIO Calibration-IP path.

This path is now validated on the production `A5EB013BB23BE4SCS` device. A
self-starting MemTest diagnostic changed the PLL from its 80 MHz power-up
profile to 52 MHz, observed unlock and relock, and independently counted 5.2
million output-clock edges during a 0.1 second 50 MHz reference window. It
returned diagnostic code 52 through the HPS GPI for 30 consecutive samples.
This rules out the reported revision-1 variable-PLL limitation for this board.
The earlier failure was the controller's accidental use of the HVIO-only
`0x48[14]` write, not a silicon erratum. The proof image is
`artifacts/memtest/MemTest_20260814_PLL_DIAG.rbf`; after loading it, run
`mister-de25-pll-diagnostic` as root on the board to repeat the check.

MemTest also quiesces the onboard SDRAM and waits for a clock-domain
acknowledgement before changing its clock. NES extends the same transport to
five related outputs and waits for its SDRAM controller to finish any active
command before switching between NTSC and PAL profiles.
Quartus derives NTSC at 85.909091/42.954545/21.477273 MHz and PAL at
85.119048/42.559524/21.279762 MHz. The PAL error is 0.0076 percent and SDRAM
launch/capture phase error is below 30 ps. The shared runtime PLL transport is
hardware-validated. Individual cores still require their own reset, memory,
and video validation after integration.

## Delivery order

1. Agilex HPS transport and FPGA reconfiguration.
2. Native 128 MB SDRAM and shared LPDDR4 interfaces.
3. HDMI video and audio, USB input, Ethernet, and SD storage.
4. ARM64 build of Main_MiSTer and the Menu core.
5. PC110, InputTest, MemTest, NES, SNES, and Minimig validation.
6. Automated builds and compatibility reports for the official core catalog.

The common top in `rtl/de25_mister_menu_top.sv` implements the reusable
`de25_mister_top` board boundary for every core. Capability macros select only
interface variants such as the 46/49-bit HPS bus, framebuffer ports, and split
SDRAM data pins. `rtl/de25_mister_gp_bridge.sv` preserves
the GPO/GPI handshake used by Main_MiSTer while moving the registers behind the
Agilex lightweight HPS-to-FPGA bridge.
`rtl/de25_mister_reset_control.sv` lets a JTAG-loaded core leave reset after a
short standalone timeout when the HPS has no bootable SD card. As soon as Main
sends its first reset command, Main owns reset sequencing and an HPS reset
holds the core until the service sends a new release command.

The HPS subsystem can be exported as a reusable Quartus design partition.
Use `DE25_HPS_PARTITION_MODE=source` with
`DE25_HPS_PARTITION_EXPORT_SNAPSHOT=synthesized` to create the portable HPS
QDB, then use `DE25_HPS_PARTITION_MODE=reuse` and
`DE25_HPS_PARTITION_QDB=<file>` in Menu and core builds. The synthesized form
is the production-safe choice for Quartus Pro 25.3.1: importing a final fitted
Agilex 5 HPS snapshot can trigger an internal PTI routing-consistency error.
The synthesized QDB keeps the common HPS netlist and I/O configuration while
allowing each complete image to be fitted coherently.

`ip/create_mister_hps.tcl` adds the corresponding 32-bit output and input PIOs
at lightweight-bridge offsets `0x20000` and `0x20010`. It also connects them to
the GHRD JTAG master for recovery and diagnostics.

The ARM64 Main work is kept as patches under `patches/Main_MiSTer`. Apply them
to a clean upstream checkout with `scripts/apply-main-patches.sh`, then build
in the reproducible AArch64 container with `scripts/build-main-aarch64.sh`.
The build publishes the canonical executable and SHA-256 sidecar as
`artifacts/main/MiSTer`; both the updater and SD image builder consume that
release artifact instead of a mutable file in the source checkout.

Menu's Quartus portability overlay is kept under `patches/Menu` and is applied
idempotently by `scripts/build-menu.sh`. The emulation logic remains upstream.
The patches scope PS/2 staging signals portably, replace one Cyclone V-specific
SDRAM clock primitive, make implicit declarations explicit, and expose the
SDRAM data output-enable at the `emu` boundary so Agilex creates physical
bidirectional buffers correctly.

Every FPGA build first refreshes `vendor/terasic-ghrd` from the immutable
`vendor/terasic-ghrd-pristine` baseline. This is required because Quartus
upgrades the imported HPS IP files in place. Starting one build from the
previous build's upgraded tree changes the HPS I/O hash and produces a runtime
RBF that cannot safely be loaded over the QSPI platform image. A shared build
lock serializes the catalog so concurrent cores cannot replace that generated
HPS tree while Quartus is compiling it. Each wrapper then runs IP generation,
synthesis, fitting, assembly, and timing as explicit stages. This prevents the
monolithic Quartus flow from regenerating the HPS IP a second time and changing
the platform hash.

Menu, PC110, PCXT, ao486, InputTest, MemTest, NES, SNES, Minimig,
TurboGrafx16, Apple-I, and SMS have completed Agilex 5 synthesis, fitting,
assembly, timing analysis, and generation of runtime images matching the
board's HPS I/O platform. The build matrix marks eight cores as packaged.
PCXT, SMS/Game Gear, and ao486 are registered as Platform V2 builds with zero
timing violations, but remain hardware-pending until gameplay is validated.
ao486's main DDR-backed PC memory path and its separate GUS native-SDRAM path
are both present. The GUS interface uses a related phase-shifted physical
clock, frequency-aware refresh scheduling, and timing-checked bidirectional
data I/O; real GUS playback remains hardware-pending.
The ARM64 Main executable, runtime FPGA-region
loader, bridge lifecycle helper, boot services, and final SD image build are
reproducible. The image is `artifacts/mister-de25.img`, with Menu preloaded at
boot. Real-board validation has confirmed SD boot, Ethernet and SSH, the ARM64
Main service, FPGA-region runtime loading, FPGA operating state, and the MiSTer
GPO/GPI handshake. The ADV7513 diagnostic color-bar image has produced visible
HDMI output, and a board-compatible integrated Menu image now produces its OSD
and settings screen. Apple-I and SMS have both been switched into the live
fabric through the guarded runtime path; Main identified each core and a native
framebuffer screenshot confirmed Apple-I video plus readable OSD composition.
The Menu raster's previously observed lower-edge clipping still requires a
fresh hardware recheck. The registered non-Menu cores all use the common shell
and automated build path. Minimig preserves its related
113.5/28.375 MHz PAL clocks, switches to 114.74359/28.685897 MHz for NTSC, and
uses the board's native SDRAM at half of the high-speed clock.

`scripts/core-inventory.sh` reports the interface version and Cyclone-specific
surface area of fetched cores. It intentionally flags newer interface variants
instead of silently compiling them against the wrong shell.

`scripts/fetch-official-core.sh HOME` fetches one repository by its locked
official catalog identity without overwriting a modified checkout.
`scripts/official-port-inventory.sh` emits a complete 307-entry readiness table
covering fetched state, `emu` top, HPS bus generation, Cyclone-specific source
surface, DDRAM, and SDRAM. This is the common intake path for expanding beyond
the first packaged cores.

`scripts/refresh-build-matrix.sh` clones the official MiSTer Wiki at one exact
commit, converts its core list to `official-core-catalog.tsv`, and records the
Wiki revision plus source and catalog SHA-256 values in
`official-core-catalog.lock`. A separate `local-core-catalog.tsv` records PC110
without changing that upstream identity. The resulting `build-matrix.tsv`
currently tracks 306 official entries from 296 repositories plus one local
supplemental core. `scripts/build-catalog.sh --list`
reports the DE25-supported subset, while `--supported` rebuilds every packaged
entry through its registered script. `--registered` additionally rebuilds
ports such as SMS that have a complete build path but are still awaiting
release qualification. Existing Cyclone V releases remain
catalog inputs only and are never mistaken for Agilex programming files.

After exporting a fitted HPS design partition, run
`scripts/rebuild-platform-release.sh --hps-qdb FILE --hps-hash FILE`. It
rebuilds ARM64 Main, Menu, and every registered core against that exact
partition, verifies every RBF digest and HPS I/O identity, and can optionally
produce the update bundle with `--bundle DIRECTORY` and a new SD image with
`--image BASE.img OUTPUT.img`. A mixed platform cannot reach either packaging
step.

The individual Docker build wrappers accept either host paths inside the
workspace or `/work/PC110-Mister/...` paths for partition QDBs, compatibility
hashes, and optional output files. Host paths are mapped into the container
automatically. Paths outside the mounted workspace are rejected before Docker
starts, which prevents a long Quartus run from failing on an inaccessible QDB.

`scripts/build-platform-candidates.sh` builds a named, compatibility-locked
candidate set without replacing the currently packaged release. It verifies
the HPS identity and SHA-256 sidecars after every core, can reuse candidates
that already pass those checks, and publishes a manifest only after the whole
requested set succeeds.

`scripts/make-update-bundle.sh` creates a SHA-256 and size-verified update
bundle containing Main, Menu, every core with a registered build artifact in
the locked matrix, the FPGA-region loader, and boot services. The generated
runtime catalog includes the same managed set, including timing-clean ports
that still await hardware validation. `MISTER_DE25_MENU_RBF` and
`MISTER_DE25_PLATFORM_HASH_FILE` select a matched alternate platform such as
Menu-v2. The SD image builder reads the same matrix, so newly validated ports
do not require a second hardcoded release list. Run `Scripts/update_de25.sh`
from the image with either a local bundle directory or an HTTPS bundle URL.
The updater stages every payload before installation, retains `.previous`
copies, and rolls back files already switched if a later install step fails.
RBF sidecars are mandatory and every runtime hash must match the installed
QSPI platform hash. SD image creation enforces the same invariant before
copying anything and reads every RBF and sidecar back from the resulting FAT
filesystem.

For real-board validation before installation,
`sw/mister-de25-test-rbf CANDIDATE.rbf ROLLBACK.rbf [CONTENT.mgl]` stops Main,
loads the compatibility-checked candidate, and restarts Main without replacing
the boot Menu. The optional absolute MGL or MRA path launches test content in
the same root-owned, one-shot service start, which supports unattended core
validation. Candidate startup now completes as soon as Main consumes the
one-shot marker, remains active, and the authoritative FPGA load record matches
the requested path and digest. A short stability window replaces the former
fixed five-second delay.

The common scaler stores a native RGB copy of the displayed frame in the
logical `0x30000000` LPDDR4 window, separate from core DDRAM. Main's standard
MiSTer screenshot path reads that window on DE25. Run
`mister-de25-screenshot [--scaled] [NAME]` over SSH to request a PNG, wait
until Main has finished writing it, and print its absolute path beneath
`/media/fat/screenshots`. This captures the FPGA video stream directly and
does not depend on a camera or HDMI capture device. From the development host,
`scripts/capture-board-screenshot.sh [OUTPUT.png]` requests a new frame over
SSH, retrieves it through the configured jump host, validates its PNG header,
and saves it under `artifacts/screenshots` by default.

All runtime FPGA programming, including requests made by Main, passes through
`mister-de25-load` beneath the HPS hardware watchdog. The loader records a
persistent pending transaction before touching configfs and clears it only
after FPGA user mode and bridge re-enable. A kernel, SDM, or FPGA-manager stall
therefore resets the HPS and the next boot restores Menu. If Menu itself caused
the watchdog reset, preload skips the repeated Menu load once and leaves the
QSPI recovery fabric active so Ethernet and JTAG remain reachable instead of
forming a reboot loop. The watchdog helper refuses to program unless the
hardware watchdog exists. Agilex's DesignWare watchdog cannot be stopped once
started, so a resident keeper owns it and pets it between loads. The loader
pauses the keeper before programming and resumes it only after FPGA user mode
and bridge recovery, leaving a failed or hung transaction to reset the HPS.
The keeper acknowledges pause and resume within 100 milliseconds, and the
loader reuses a compatibility result across its watchdog re-entry only while
the RBF device, inode, size, and timestamps remain unchanged. This removes
duplicate payload hashing without weakening the guarded transaction.

Boot Menu is also stored as a digest-checked root-filesystem cache under
`/var/lib/mister-de25/boot`. The preload service can therefore configure the
mandatory HPS-first phase-2 image while the FAT partition is still mounting.
Main still starts only after `/media/fat` is available. Update bundles, new SD
images, and platform migration install or roll back the cached and FAT copies
together, so early loading never bypasses the platform-hash interlock.

QSPI changes are intentionally separate from ordinary updates. The guarded
`scripts/program-qspi.sh` command requires an explicit JTAG index and literal
confirmation, extracts both hashes with Quartus, refuses a JIC/runtime mismatch,
and programs with verification. It is not run by the updater or image builder.
When only a known-good HPS-first phase-1 RBF survives,
`scripts/make-qspi-jic-from-hps-rbf.sh` packages it as a DE25 ASx4 recovery JIC
and verifies that the JIC preserves the phase-1 HPS I/O hash.

For a board already stranded before the guarded loader is installed, the
reference HPS shell already provides a separate coherent JTAG-to-HPS master.
`scripts/hps-watchdog-probe.tcl` identifies it from the DesignWare watchdog
component signature, and `scripts/hps-watchdog-reset.tcl` refuses to write
until it finds that signature. No alternate HPS address-space mapping is
required. A board that appears stuck after JTAG programming must first be
checked for the correct phase-1 `.hps.rbf`; programming a converted SOF leaves
the HPS-first transaction incomplete. `DE25_HPS_RESET_RECOVERY=1` remains a
targeted runtime-handshake diagnostic and is not part of the boot procedure.
Production builds retain the normal active-low protocol: the shell holds all
HPS-facing soft logic in reset
immediately when SDM requests a warm reset, and
asserts acknowledgement only after that reset has settled for three
independent FPGA clock edges. Request deassertion is synchronized before reset
and acknowledgement are released. This removes the configuration-time race
caused by acknowledging before the soft logic is actually in reset. Every
`make-hps-first-rbf.sh` invocation emits the two images required by the Agilex
5 HPS-first flow. The `.hps.rbf` is phase 1 and contains the HPS I/O shell plus
SPL. The `.core.rbf`, also copied to the requested runtime `.rbf`, is phase 2.
For a cold JTAG boot, program the phase-1 image with
`scripts/program-hps-first-jtag.sh IMAGE.hps.rbf`, wait for Linux to boot, then
load the matching runtime image through `mister-de25-load`. Do not program a
converted `.jtag.sof`: it does not perform the required split HPS-first
transaction and can leave the board in phase 1 without the runtime fabric or
its JTAG services.

Changing the HPS platform hash requires
`sw/mister-de25-platform-migration`. Its `prepare` command backs up the
installed Menu and platform hash, stages the new Menu, creates a persistent
load interlock, and stops Main while leaving the resident hardware-watchdog
keeper active. Program and verify the matched JIC separately,
then record that success with `flashed --confirm FLASH-VERIFIED`. The helper
installs the matched Menu and platform hash but keeps all FPGA loads blocked
until a real reboot changes the Linux boot ID. The preload service calls
`finalize-boot` before loading Menu. A power failure before or after QSPI
programming therefore boots Linux into a recoverable state without attempting
an incompatible phase-2 load. `abort` is valid before flashing. After restoring
the source JIC, use `restore-files --confirm QSPI-ROLLED-BACK` to restore the
backed-up SD state.

Installed systems also provide a non-interactive remote coordinator. Run
`mister-de25-migrate stage TARGET_MENU.rbf`, wait until
`mister-de25-migrate status` reports `waiting-for-qspi`, and program the
matching JIC with `scripts/program-qspi.sh`. Only after Quartus programming and
verification succeeds, run
`mister-de25-migrate verified --confirm FLASH-VERIFIED`. A systemd path unit
launches the root migration controller, so these fixed operations do not need
an interactive sudo prompt. `mister-de25-migrate cancel` safely aborts only the
pre-flash prepared state. The controller checks the RBF digest and HPS hash at
each boundary and times out to the original Menu if verification never arrives.

## Local checks

```sh
mister-de25/scripts/test.sh
```
