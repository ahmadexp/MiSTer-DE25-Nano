# PSX, Saturn, and N64 port plan

This plan starts only after the shared Platform V2 shell and several small
personas have reproduced clean builds. The large cores are not simple clock
translations. Their memory topology, framebuffer traffic, and resource use
must fit alongside an 8,132 ALM shell on an A5EB013 device with 46,800 ALMs,
358 RAM blocks, and 7,331,840 block-memory bits.

## Small-core baseline results

- AY-3-8500: timing-clean RBF and clean native hardware video capture.
- CHIP-8: timing-clean RBF, guarded live load, and clean native hardware
  splash capture. The port also replaces its data-pulse keyboard clock and
  fully constrains its slow divider domains.
- NES and InputTest: packaged images load, the HPS payload identity matches,
  and the FPGA reports operating, but both currently capture as a uniform
  gray frame. Because CHIP-8 renders correctly through the same board and
  capture path, this is tracked as a shared legacy-persona video regression,
  not as two independent core failures.
- Game of Life: elaborates, but its upstream 2.47-million-cell ring maps to
  1,241 M20K blocks. The A5EB013 has 358, so this is a DDR-memory redesign
  candidate rather than a small compatibility port.

## Port order

1. **PSX**: first bring-up target. It uses the legacy 46-bit HPS bus already
   supported by the shell, one native SDRAM interface, the standard DDRAM
   channel, and a direct framebuffer interface.
2. **N64**: second target. It uses the 49-bit HPS bus, one native SDRAM
   interface for cartridge storage, DDRAM for RDRAM, and a framebuffer.
3. **Saturn**: third target. Upstream recommends two independently accessible
   SDRAM modules. The DE25-Nano's two SDRAM devices share command, address,
   and data wiring, so the secondary memory role must be moved to HPS DDR or
   arbitrated through the shared rank bus before compatibility can match the
   dual-SDRAM MiSTer build.

## Current build status

| Persona | Build | Worst setup | ALMs | M20Ks | Hardware gate |
| --- | --- | ---: | ---: | ---: | --- |
| PlayStation | complete | +0.477 ns | 95% | 72% | guarded load passed; BIOS/content pending |
| Nintendo 64 | complete | +0.859 ns | 93% | 46% | load and content pending |
| Sega Saturn LIGHT | complete | +0.051 ns | 97% | 74% | load and content pending |

All three bitstreams assemble successfully, have zero failing setup and hold
endpoints, have zero unconstrained paths, and carry the exact FDCD HPS I/O
compatibility hash used by Menu V2. These are installable bring-up candidates,
not yet functionally complete ports. Runtime region switching, broad software
compatibility, controllers, video modes, and audio still require hardware
validation.

## PSX phase gates

The fixed-NTSC PSX bring-up persona now completes synthesis, fit, assembly,
static timing, HPS-first packaging, and a guarded load on the DE25-Nano. Its
worst global setup slack is +0.477 ns, SDRAM input setup/hold is
+0.477/+11.117 ns, and SDRAM output setup/hold is +0.913/+1.555 ns. All
endpoints are constrained. The design uses a C4 to falling-C2 to rising-C2
capture pipeline, which adds one latency cycle while retaining one SDRAM word
per cycle. The remaining gate is a real BIOS and game boot with video, input,
storage, and audio validation.

The checked-in `DE25_MISTER_PSX_V2` project is the first compile gate:

- Core clocks: 33.8688, 67.7376 with the original phase relationship, and
  101.6064 MHz.
- Initial video clock: fixed NTSC 53.693175 MHz.
- Memory: native onboard SDRAM plus the Platform V2 DDRAM bridge.
- Video: native PSX video plus the existing DE25 scaler and framebuffer path.
- Runtime PAL and fast-forward clock switching: deferred until synthesis,
  fitting, timing, and an NTSC BIOS boot pass.

The initial Agilex memory blocker in upstream `dpram.vhd` is resolved. The
port now uses explicit same-clock, simple dual-port, and related-clock memory
adapters selected according to each RAM's actual access pattern. This work is
independent of the PLL.

The PSX memory work is now split into three explicit adapters:

1. Same-clock true dual-port RAM for the many ordinary core memories.
2. Dual-clock simple dual-port RAM for one-writer, one-reader crossings such
   as the CPU caches, scratchpad, and video path.
3. A small related-clock dual-writer implementation for joypad memory, whose
   behavior cannot be preserved by a simple family-string substitution.

## N64 clock and memory intake

- Core clocks requested upstream: 62.5, 93.75, and 125 MHz.
- Runtime video clock starts at 48.68 MHz and changes by region/mode.
- HPS interface: 49 bits.
- Memory: native SDRAM for ROM and save storage, HPS DDRAM for RDRAM.
- First bring-up mode: fixed NTSC video clock, cartridge loading, no runtime
  video-clock changes until the base memory path is proven.
- Checked-in compile gate: `DE25_MISTER_N64_V2`, with Agilex PLL wrappers,
  explicit MEM-library assignments, 49-bit HPS I/O, native SDRAM, and the
  common Platform V2 shell.

The first compile gate now passes SystemVerilog/VHDL elaboration far enough to
generate the complete native memory netlist. The fixed 48.68 MHz video clock
and the 62.5, 93.75, and 125 MHz core clocks all generate successfully.
Quartus then reports the same Agilex 5 memory restriction seen by PSX, across
18 generated dual-clock bidirectional RAMs. It also finds asymmetric true
dual-port widths (including 64/32, 64/16, 32/16, 32/8, 32/2, and 16/32) and
two shift-tap memories that still request the Cyclone V-only `M10K` block
name. The earlier RDP 36-bit port-association error has been corrected.

The N64 memory conversion completed these steps:

1. Replaced equal-width one-writer/one-reader crossings with Agilex-compatible
   simple dual-port RAMs.
2. Implemented explicit packing adapters for asymmetric-width crossings.
3. Audited the remaining true dual-writer cases and preserved collision behavior.
4. Replaced Cyclone V-only `M10K` selections with Agilex-compatible memory.

The resulting fixed-NTSC image fits at 93% ALMs and 46% M20Ks with +0.859 ns
worst setup slack. Runtime video-clock changes remain deferred until cartridge
loading and base NTSC video are proven on hardware.

## Saturn clock and memory intake

- Primary core clocks requested upstream: 57.272799 and 114.545598 MHz.
- HPS interface: 49 bits.
- Upstream hardware recommendation: primary 128 MB SDRAM plus a secondary
  32 to 128 MB SDRAM module.
- Checked-in compile gate: `DE25_MISTER_SATURN_V2`, using `LIGHT_SATURN`, one
  native SDRAM interface, fixed NTSC clocks, 49-bit HPS I/O, and the common
  Platform V2 shell.
- Later engineering task: route the optional secondary-memory transactions to
  HPS DDR without changing the latency contract seen by the Saturn core.

The Quartus 25 language-compatibility pass, nested CPU/DSP manifests, VHDL
library assignments, and fixed clock pair are complete. The LIGHT_SATURN
persona maps VDP2 and SCSP to native SDRAM and the remaining large-memory role
to HPS LPDDR4. It fits at 97% ALMs and 74% M20Ks with +0.051 ns worst setup
slack. That narrow margin and the translated secondary-memory latency contract
make guarded hardware loading and a real BIOS/content boot the next gates.

## Acceptance sequence for every large core

1. Quartus elaboration with no Cyclone V-only IP remaining.
2. Fitter completion with recorded ALM, RAM block, DSP, PLL, and pin use.
3. Timing pass using the common Platform V2 constraints.
4. HPS I/O hash equality with the FDCD menu platform.
5. Safe runtime load, automatic fallback to Menu, and no HPS reboot loop.
6. Stable HDMI, OSD, controller, storage, and audio checks.
7. BIOS or cartridge boot, followed by PAL/NTSC and runtime-clock testing.
