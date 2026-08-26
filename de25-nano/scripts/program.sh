#!/usr/bin/env bash
set -euo pipefail

target_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
program_image=${1:-$target_root/artifacts/DE25_PC110_DIAG.sof}
device_index=${DE25_JTAG_INDEX:-1}
quartus_image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}

if [[ ! -f $program_image ]]; then
    echo "FPGA programming image not found: $program_image" >&2
    exit 1
fi

if command -v quartus_pgm >/dev/null 2>&1; then
    jtagconfig
    exec quartus_pgm -m jtag -o "p;$program_image@$device_index"
fi

image_dir=$(cd "$(dirname "$program_image")" && pwd)
image_name=$(basename "$program_image")
docker run --rm --privileged --network host \
    -v /dev/bus/usb:/dev/bus/usb \
    -v "$image_dir:/work:ro" \
    -w /work \
    "$quartus_image" sh -lc \
    "jtagconfig && quartus_pgm -m jtag -o 'p;$image_name@$device_index'"
