#!/usr/bin/env bash
set -euo pipefail

target_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
archive=${1:-${DE25_RESOURCE_ARCHIVE:-/tmp/DE25-Nano_revB_v.1.0.0_ResourcePackage.zip}}
vendor_root="$target_root/vendor/terasic-ghrd"
prefix='Demonstration/SoC_FPGA/GHRD'

if [[ ! -f $archive ]]; then
    echo "Terasic rev-B resource archive not found: $archive" >&2
    echo "Pass its path as the first argument or set DE25_RESOURCE_ARCHIVE." >&2
    exit 1
fi

mkdir -p "$vendor_root/hps_subsys/ip/hps_subsys" \
    "$vendor_root/hps_subsys/ip/hps_subsys/f2sdram_adapter/f2sdram_adapter_10/synth" \
    "$vendor_root/hps_subsys/ip/hps_subsys/f2sdram_adapter/synth" \
    "$vendor_root/hps_subsys/ip/qsys_top" \
    "$vendor_root/ip/qsys_top" \
    "$vendor_root/jtag_subsys/ip/jtag_subsys" \
    "$vendor_root/peripheral_subsys/ip/peripheral_subsys"

for relative in \
    board.info \
    golden_top.qsf \
    golden_top.v \
    ghrd_timing.sdc \
    qsys_top.qsys \
    hps_subsys/board.info \
    hps_subsys/hps_subsys.qsys \
    hps_subsys/ip/hps_subsys/agilex_hps.ip \
    hps_subsys/ip/hps_subsys/f2sdram_adapter.ip \
    hps_subsys/ip/hps_subsys/f2sdram_adapter/f2sdram_adapter.cmp \
    hps_subsys/ip/hps_subsys/f2sdram_adapter/f2sdram_adapter.qip \
    hps_subsys/ip/hps_subsys/f2sdram_adapter/f2sdram_adapter.qgsynthc \
    hps_subsys/ip/hps_subsys/f2sdram_adapter/f2sdram_adapter.sopcinfo \
    hps_subsys/ip/hps_subsys/f2sdram_adapter/f2sdram_adapter.xml \
    hps_subsys/ip/hps_subsys/f2sdram_adapter/f2sdram_adapter_10/synth/f2sdram_adapter_f2sdram_adapter_10_ebbsmiq.v \
    hps_subsys/ip/hps_subsys/f2sdram_adapter/synth/f2sdram_adapter.v \
    hps_subsys/ip/qsys_top/emif_io96b_hps.ip \
    ip/qsys_top/clk_100.ip \
    ip/qsys_top/ext_hps_f2sdram_master.ip \
    ip/qsys_top/ocm.ip \
    ip/qsys_top/qsys_top_ace5lite_cache_coherency_translator_0.ip \
    ip/qsys_top/rst_in.ip \
    ip/qsys_top/user_rst_clkgate_0.ip \
    jtag_subsys/board.info \
    jtag_subsys/jtag_subsys.qsys \
    jtag_subsys/ip/jtag_subsys/fpga_m.ip \
    jtag_subsys/ip/jtag_subsys/hps_f2sdram.ip \
    jtag_subsys/ip/jtag_subsys/hps_m.ip \
    jtag_subsys/ip/jtag_subsys/jtag_clk.ip \
    jtag_subsys/ip/jtag_subsys/jtag_rst_in.ip \
    peripheral_subsys/ip/peripheral_subsys/button_pio.ip \
    peripheral_subsys/ip/peripheral_subsys/dipsw_pio.ip \
    peripheral_subsys/ip/peripheral_subsys/led_pio.ip \
    peripheral_subsys/ip/peripheral_subsys/pb_cpu_0.ip \
    peripheral_subsys/ip/peripheral_subsys/periph_clk.ip \
    peripheral_subsys/ip/peripheral_subsys/periph_rst_in.ip \
    peripheral_subsys/ip/peripheral_subsys/sysid.ip \
    peripheral_subsys/peripheral_subsys.qsys
do
    unzip -p "$archive" "$prefix/$relative" > "$vendor_root/$relative"
done

echo "Imported Terasic GHRD Platform Designer sources into $vendor_root"
