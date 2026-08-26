#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${TMPDIR:-/tmp}/mister-de25-tgfx16-memory

mkdir -p "$build_dir"
iverilog -g2012 -s de25_dpram_difclk_tb \
    -o "$build_dir/de25_dpram_difclk_tb" \
    "$platform_root/sim/altsyncram_model.sv" \
    "$platform_root/upstream/cores/TurboGrafx16/rtl/de25_dpram_difclk.sv" \
    "$platform_root/sim/de25_dpram_difclk_tb.sv"
vvp "$build_dir/de25_dpram_difclk_tb"
