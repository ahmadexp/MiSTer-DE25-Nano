#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: prepare-sd-image.sh BASE.img PC110_BIOS.bin PC110_FONT.bin OUTPUT.img

Creates a new PC110 boot image without modifying BASE.img. The output embeds
the supplied private ROM files, so keep it local and do not publish it.
EOF
}

if [[ $# -ne 4 ]]; then
    usage >&2
    exit 2
fi

base_image=$1
bios=$2
font=$3
output_image=$4
script_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fat_offset=1048576

for tool in dtc fdtoverlay mkimage mcopy mdir; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required tool is missing: $tool" >&2
        exit 1
    fi
done

for input in "$base_image" "$bios" "$font"; do
    if [[ ! -f $input ]]; then
        echo "Input file not found: $input" >&2
        exit 1
    fi
done

if [[ $base_image == "$output_image" ]]; then
    echo "OUTPUT.img must be different from BASE.img" >&2
    exit 1
fi

if [[ -e $output_image ]]; then
    echo "Refusing to overwrite existing output: $output_image" >&2
    exit 1
fi

if [[ $(wc -c <"$bios") -ne 262144 ]]; then
    echo "PC110 BIOS must be exactly 262144 bytes" >&2
    exit 1
fi

if [[ $(wc -c <"$font") -ne 1048576 ]]; then
    echo "PC110 font ROM must be exactly 1048576 bytes" >&2
    exit 1
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/pc110-sd.XXXXXXXX")
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

echo "Copying the Terasic base image..."
if cp --reflink=auto --sparse=always "$base_image" "$output_image" 2>/dev/null; then
    :
else
    cp "$base_image" "$output_image"
fi

image_spec="$output_image@@$fat_offset"
mcopy -n -i "$image_spec" ::/socfpga_agilex5_de25_nano.dtb "$work_dir/base.dtb"

dtc -q -@ -I dts -O dtb \
    -o "$work_dir/pc110-memory.dtbo" \
    "$script_root/boot/pc110-memory-overlay.dts"
fdtoverlay \
    -i "$work_dir/base.dtb" \
    -o "$work_dir/socfpga_agilex5_de25_nano.dtb" \
    "$work_dir/pc110-memory.dtbo"

mkimage \
    -A arm64 -O linux -T script -C none \
    -n "DE25-Nano PC110 boot" \
    -d "$script_root/boot/boot-pc110.cmd" \
    "$work_dir/boot.scr.uimg"

mcopy -o -i "$image_spec" \
    "$work_dir/socfpga_agilex5_de25_nano.dtb" \
    ::/socfpga_agilex5_de25_nano.dtb
mcopy -o -i "$image_spec" "$work_dir/boot.scr.uimg" ::/boot.scr.uimg
mcopy -o -i "$image_spec" "$bios" ::/pc110_bios.bin
mcopy -o -i "$image_spec" "$font" ::/pc110_font.bin

mcopy -n -i "$image_spec" ::/socfpga_agilex5_de25_nano.dtb "$work_dir/check.dtb"
dtc -q -I dtb -O dts -o "$work_dir/check.dts" "$work_dir/check.dtb"
grep -q 'pc110@b0000000' "$work_dir/check.dts"
grep -q 'reg = <0x00 0x80000000 0x00 0x40000000>' "$work_dir/check.dts"

echo
echo "PC110 boot image ready: $output_image"
echo "Reserved LPDDR: 0xb0000000 through 0xbfffffff"
echo "BIOS preload:    0xb00c0000"
echo "Font preload:    0xb2000000"
mdir -i "$image_spec" ::
