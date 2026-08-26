#!/usr/bin/env bash
set -euo pipefail

target_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

iverilog -g2012 -Wall \
    -s de25_pc110_diag \
    -o /tmp/de25_pc110_diag.vvp \
    "$target_root/sim/reset_release_stub.sv" \
    "$target_root/rtl/adv7513_init.sv" \
    "$target_root/rtl/de25_pc110_diag.sv"

iverilog -g2012 -Wall \
    -s de25_pc110_diag_tb \
    -o /tmp/de25_pc110_diag_tb.vvp \
    "$target_root/sim/reset_release_stub.sv" \
    "$target_root/rtl/adv7513_init.sv" \
    "$target_root/rtl/de25_pc110_diag.sv" \
    "$target_root/sim/de25_pc110_diag_tb.sv"
vvp /tmp/de25_pc110_diag_tb.vvp
