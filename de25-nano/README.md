# PC110 on DE25-Nano

This directory is an isolated Quartus Prime Pro target for the Terasic
DE25-Nano rev B (`A5EB013BB23BE4SCS`, Agilex 5). It leaves the existing
DE10-Nano MiSTer target intact.

## Current state

`DE25_PC110_PORT` now synthesizes and fits the complete PC110 FPGA core with:

- 30 MHz PC system, 90 MHz VGA, UART, MPU, and OPL clock domains;
- the ao486 CPU, PC110 chipset, caches, VGA, and legacy peripherals;
- 24-bit video through the board's ADV7513 HDMI transmitter;
- a 64-bit clock-crossing bridge from the 30 MHz core to HPS LPDDR4;
- the Terasic HPS, LPDDR4, SD, USB, Ethernet, UART, and JTAG infrastructure;
- a deliberate `SW0` run interlock so ROM and RAM can be prepared first.

The August 11, 2026 build uses 29,236 of 46,800 ALMs (62 percent) and 304 of
358 M20Ks (85 percent). Quartus reports zero failing endpoints and timing
closure in every internal clock domain. The worst setup slack is 4.245 ns.

This is a hardware bring-up build, not a finished MiSTer replacement. The HPS
management connections for keyboard, mouse, disks, configuration, and audio
are still tied off. Initial validation therefore targets BIOS execution, POST
output on the FPGA UART, and HDMI video.

The pin assignments and HPS platform come from Terasic's
`DE25-Nano_revB_v.1.0.0_ResourcePackage.zip` Golden Top and HDMI projects.

## Artifacts

| File | Purpose |
| --- | --- |
| `DE25_PC110_PORT.sof` | Compiled FPGA image, before adding the HPS SPL |
| `DE25_PC110_PORT_HPS.sof` | Programmable PC110 image with the HPS SPL |
| `DE25_PC110_DIAG.sof` | Safe 640x480 HDMI, clock, key, switch, and LED diagnostic |
| `DE25_PC110_CLOCKS.sof` | Obsolete clock-only development image |
| `DE25_PC110_CORE_SMOKE.sof` | Obsolete early core smoke image |

Do not use the two obsolete development images. The full port requires HPS
LPDDR to be initialized before the x86 core is released.

## Build

Quartus Prime Pro 25.3.1 with Agilex 5 support is required. The local build
script uses native Quartus when available, otherwise Altera's official
container. Set `DE25_BUILD_HOST` to the Quartus SSH target before using a
remote build script.

```sh
mister-de25/scripts/fetch-core-catalog.sh
de25-nano/scripts/lint.sh
DE25_BUILD_HOST=user@quartus-builder \
de25-nano/scripts/build-port-remote.sh
```

The full SOF and Fit/Timing Analyzer reports are copied into
`de25-nano/artifacts/`.

The Agilex 5 HPS requires bootloader data in the programming SOF. Copy the
official Terasic `u-boot-spl-dtb.hex` into `de25-nano/artifacts/`, or pass its
path to `program-port-remote.sh`. The programming script packages a fresh
`DE25_PC110_PORT_HPS.sof`, programs it, and copies that artifact back locally.

## LPDDR layout

The production DE25-Nano calibrates 1 GiB of LPDDR at `0x80000000`, although
Terasic's supplied Linux device tree advertises 2 GiB. The boot overlay corrects
that size and keeps the top 256 MiB private to the PC110:

| Physical address | Use |
| --- | --- |
| `0x80000000` through `0xAFFFFFFF` | Linux and the Terasic service buffer |
| `0xB0000000` through `0xBFFFFFFF` | PC110 256 MiB memory window |
| `0xB00C0000` | 256 KiB PC110 BIOS preload |
| `0xB2000000` | 1 MiB PC110 font preload |

The supplied device-tree overlay marks the PC110 window `no-map`, preventing
Linux from allocating or mapping its live cache lines.

## Prepare the SD image

Start with Terasic's DE25-Nano console SD image. The preparation script makes a
new image and never changes its base image. It requires `dtc`, `fdtoverlay`,
`mkimage`, and mtools.

```sh
de25-nano/scripts/prepare-sd-image.sh \
  de25_nano_revA_sdcard_console_v1.1.img \
  artifacts/roms/pc110_bios.bin \
  artifacts/roms/pc110_font.bin \
  pc110-de25.img
```

The output contains the private PC110 ROMs. Keep it local and do not publish
it. Before writing it to a card, verify the exact removable device with
`lsblk`. Never infer the destination from a device name and never select the
host's NVMe system disk.

## First hardware boot

1. Write `pc110-de25.img` to the microSD in an external card reader.
2. Insert the card in the DE25-Nano and keep `SW0` low.
3. Power-cycle the board and let the HPS initialize LPDDR and boot Linux.
4. Program the full port over JTAG. The default SPL path is
   `de25-nano/artifacts/u-boot-spl-dtb.hex`; an alternate path can be supplied
   as the first argument:

   ```sh
   de25-nano/scripts/program-port-remote.sh
   ```

5. Reload and byte-for-byte verify the ROMs after FPGA configuration:

   ```sh
   de25-nano/scripts/preload-roms-remote.sh
   ```

6. Raise `SW0` to release the x86 core. Watch HDMI and the FPGA UART for BIOS
   POST activity.

`KEY0` resets the FPGA fabric. `KEY1` restarts ADV7513 initialization. `SW1`
is passed to the core as F1 and `SW2` controls the 60 Hz option.

## Diagnostic image

The default for `program.sh` remains the safe diagnostic:

```sh
de25-nano/scripts/program.sh de25-nano/artifacts/DE25_PC110_DIAG.sof
```

With `SW2=1`, LEDs 0 through 2 blink from the three 50 MHz board oscillators.
With `SW2=0`, the LEDs report HDMI state:

| LED | Meaning |
| --- | --- |
| 0 | ADV7513 initialization completed |
| 1 | Status registers were read successfully |
| 2 | Transmitter is powered |
| 3 | HDMI hot-plug detect |
| 4 | Monitor sense |
| 5 | ADV7513 PLL lock |
| 6 | TMDS outputs powered and EDID ready |
| 7 | I2C or DDC error blink |
