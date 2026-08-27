#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
remote=${DE25_BUILD_HOST:?Set DE25_BUILD_HOST to the Quartus SSH target}
remote_stage=${DE25_REMOTE_PRELOAD_DIR:-/home/user/Downloads/de25-nano/pc110-preload}
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
bios=${1:-$repo_root/mister-de25/artifacts/private/pc110/pc110_bios.bin}
font=${2:-$repo_root/mister-de25/artifacts/private/pc110/pc110_font.bin}
design=${3:-$repo_root/de25-nano/artifacts/DE25_PC110_PORT_HPS.sof}

if [[ ! -f $bios || ! -f $font || ! -f $design ]]; then
    echo "PC110 SOF, BIOS, or font file not found" >&2
    exit 1
fi

if [[ $(wc -c <"$bios") -ne 262144 || $(wc -c <"$font") -ne 1048576 ]]; then
    echo "Unexpected PC110 BIOS or font file size" >&2
    exit 1
fi

ssh "$remote" "mkdir -p '$remote_stage'"
rsync -az \
    "$repo_root/de25-nano/scripts/preload-roms.tcl" \
    "$design" "$bios" "$font" \
    "$remote:$remote_stage/"

design_name=$(basename "$design")
bios_name=$(basename "$bios")
font_name=$(basename "$font")
ssh "$remote" "docker run --rm --privileged --network host \
    -v /dev/bus/usb:/dev/bus/usb \
    -v '$remote_stage:/work:ro' \
    '$image' sh -lc \"jtagconfig && system-console \
    --script=/work/preload-roms.tcl \
    '/work/$design_name' '/work/$bios_name' '/work/$font_name'\""
