#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF' >&2
Usage: program-hps-first-jtag.sh IMAGE.hps.rbf [JTAG_DEVICE_INDEX]

Programs only the volatile Agilex 5 HPS-first phase-1 RBF over JTAG. This
does not write QSPI. After the HPS boots Linux, load the matching phase-2
runtime RBF with mister-de25-load.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 2
fi

phase1_rbf=$1
device_index=${2:-${DE25_JTAG_INDEX:-1}}
quartus_image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}

if [[ ! -s $phase1_rbf ]]; then
    echo "HPS-first phase-1 RBF is missing or empty: $phase1_rbf" >&2
    exit 1
fi
if [[ $phase1_rbf != *.hps.rbf ]]; then
    echo "Refusing non-phase-1 image; expected a *.hps.rbf file: $phase1_rbf" >&2
    exit 1
fi
if [[ ! $device_index =~ ^[0-9]+$ ]]; then
    echo "JTAG device index must be numeric: $device_index" >&2
    exit 2
fi

echo "Programming volatile HPS-first phase 1 on JTAG device $device_index"
echo "QSPI will not be modified"

if command -v quartus_pgm >/dev/null 2>&1; then
    jtagconfig
    quartus_pgm -m jtag -o "p;$phase1_rbf@$device_index"
else
    image_dir=$(cd "$(dirname "$phase1_rbf")" && pwd)
    image_name=$(basename "$phase1_rbf")
    docker run --rm --privileged --network host \
        -v /dev/bus/usb:/dev/bus/usb \
        -v "$image_dir:/work:ro" \
        -w /work \
        "$quartus_image" sh -lc \
        "jtagconfig && quartus_pgm -m jtag -o 'p;$image_name@$device_index'"
fi

echo "HPS-first phase 1 programmed successfully"
echo "Wait for Linux, then load the matching phase-2 runtime RBF"
