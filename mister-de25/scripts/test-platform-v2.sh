#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/de25-platform-v2.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

iverilog -g2012 -s de25_i2c_register_master_tb \
    -o "$temporary_root/i2c.vvp" \
    "$platform_root/rtl/platform_v2/de25_i2c_register_master.sv" \
    "$platform_root/sim/de25_i2c_register_master_tb.sv"
vvp "$temporary_root/i2c.vvp"

iverilog -g2012 -s de25_si5332_address_probe_tb \
    -o "$temporary_root/probe.vvp" \
    "$platform_root/../de25-nano/rtl/de25_si5332_address_probe.sv" \
    "$platform_root/../de25-nano/sim/de25_si5332_address_probe_tb.sv"
vvp "$temporary_root/probe.vvp"

iverilog -g2012 -s de25_mister_audio_v2_tb \
    -o "$temporary_root/audio.vvp" \
    "$platform_root/rtl/platform_v2/de25_mister_audio_v2.sv" \
    "$platform_root/sim/de25_mister_audio_v2_tb.sv"
vvp "$temporary_root/audio.vvp"

grep -q 'DE25_PLATFORM_V2=1' \
    "$platform_root/quartus/de25_platform_v2.qsf"
grep -q 'PIN_BV14 -to SI5332_SDA' \
    "$platform_root/quartus/de25_platform_v2.qsf"
grep -q 'PIN_CG26 -to SI5332_SCL' \
    "$platform_root/quartus/de25_platform_v2.qsf"
grep -q 'GPIO_1/JP2 physical pins 1 and 2' \
    "$platform_root/quartus/de25_platform_v2.qsf"
for qsf in "$platform_root"/quartus/DE25_MISTER_*_V2.qsf; do
    grep -q 'source de25_platform_v2.qsf' "$qsf"
done
grep -q 'source de25_platform_v2.qsf' \
    "$platform_root/quartus/DE25_MISTER_MENU_V2.qsf"
grep -q 'source de25_platform_v2.qsf' \
    "$platform_root/quartus/DE25_MISTER_NES_V2.qsf"
while read -r core script_name; do
    grep -q 'source de25_platform_v2.qsf' \
        "$platform_root/quartus/DE25_MISTER_${core}_V2.qsf"
    grep -q 'TOP_LEVEL_ENTITY de25_mister_top' \
        "$platform_root/quartus/DE25_MISTER_${core}.qsf"
    grep -q 'DE25_HPS_PARTITION_MODE=reuse' \
        "$platform_root/scripts/$script_name"
done <<'EOF'
PCXT build-pcxt-v2.sh
SMS build-sms-v2.sh
AO486 build-ao486-v2.sh
EOF
while read -r core script_name wrapper_name; do
    grep -q 'source de25_platform_v2.qsf' \
        "$platform_root/quartus/DE25_MISTER_${core}_V2.qsf"
    grep -q 'DE25_HPS_PARTITION_MODE=reuse' \
        "$platform_root/scripts/$script_name"
    grep -q "SYSTEMVERILOG_FILE ../rtl/$wrapper_name" \
        "$platform_root/quartus/DE25_MISTER_${core}_V2.qsf"
done <<'EOF'
PSX build-psx-v2.sh psx_core_pll_wrapper.sv
N64 build-n64-v2.sh n64_core_pll_wrapper.sv
SATURN build-saturn-v2.sh saturn_core_pll_wrapper.sv
EOF
grep -q 'de25_platform_revision_owns_top_level' \
    "$platform_root/quartus/DE25_MISTER_MENU.qsf"
grep -q 'de25_platform_revision_owns_top_level' \
    "$platform_root/quartus/DE25_MISTER_NES.qsf"
grep -q 'profile_enable(1'"'"'b0)' \
    "$platform_root/rtl/platform_v2/de25_platform_v2_clock_service.sv"
grep -q '0b0e' "$platform_root/../de25-nano/rtl/adv7513_init.sv"
grep -q '0c04' "$platform_root/../de25-nano/rtl/adv7513_init.sv"
grep -q '7301' "$platform_root/../de25-nano/rtl/adv7513_init.sv"
grep -q 'identity=0x%024X' \
    "$platform_root/scripts/read-platform-v2-status.tcl"
grep -q 'DE25_IPGEN_PARALLEL=off' \
    "$platform_root/scripts/build-menu-v2.sh"
grep -q 'DE25_HPS_PARTITION_MODE=reuse' \
    "$platform_root/scripts/build-menu-v2.sh"
grep -q 'DE25_HPS_PARTITION_MODE:-} != reuse' \
    "$platform_root/scripts/build-menu.sh"
grep -q 'platforms/fdcd.hps-io-hash' \
    "$platform_root/scripts/build-menu-v2.sh"
grep -q 'DE25_HPS_PARTITION_MODE=reuse' \
    "$platform_root/scripts/build-nes-v2.sh"
grep -q 'mister_hps_mister_vbuf_bridge.ip' \
    "$platform_root/quartus/de25_platform_v2.qsf"
grep -q 'de25_clock_frequency_monitor.sv' \
    "$platform_root/quartus/de25_platform_v2.qsf"
grep -A3 'h2f_reset_reset(h2f_reset)' \
    "$platform_root/rtl/de25_mister_menu_top.sv" | \
grep -q 'DE25_HPS_LEGACY_NO_VBUF'

grep -q 'PIN_BV14 -to SI5332_SDA' \
    "$platform_root/quartus/DE25_MISTER_PC110.qsf"
grep -q 'PIN_CG26 -to SI5332_SCL' \
    "$platform_root/quartus/DE25_MISTER_PC110.qsf"
grep -q 'GPIO_1/JP2 physical pins 1 and 2' \
    "$platform_root/quartus/DE25_MISTER_PC110.qsf"
grep -q 'PIN_BV14 -to SI5332_SDA' \
    "$platform_root/../de25-nano/quartus/DE25_SI5332_PROBE.qsf"
grep -q 'PIN_CG26 -to SI5332_SCL' \
    "$platform_root/../de25-nano/quartus/DE25_SI5332_PROBE.qsf"
if grep -R -E 'PIN_(H16|Y1) -to SI5332_(SDA|SCL)' \
    "$platform_root/quartus" "$platform_root/../de25-nano/quartus"; then
    echo "GPIO_0 Si5332 assignment remains in a Quartus project" >&2
    exit 1
fi

echo "PASS: platform-v2 baseline keeps Si5332 writes disabled and stereo HDMI configured"
