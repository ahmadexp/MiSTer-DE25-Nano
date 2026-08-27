#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
remote=${DE25_BUILD_HOST:?Set DE25_BUILD_HOST to the Quartus SSH target}
remote_stage=${DE25_REMOTE_PROGRAM_DIR:-/home/user/Downloads/de25-nano/pc110-package}
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
device_index=${DE25_JTAG_INDEX:-1}
base_sof="$repo_root/de25-nano/artifacts/DE25_PC110_PORT.sof"
spl_hex=${1:-$repo_root/de25-nano/artifacts/u-boot-spl-dtb.hex}
phase_prefix=DE25_PC110_PORT_HPS_FIRST
phase1_rbf="$repo_root/de25-nano/artifacts/$phase_prefix.hps.rbf"
phase2_rbf="$repo_root/de25-nano/artifacts/$phase_prefix.core.rbf"

if [[ ! -f $base_sof ]]; then
    echo "Full port SOF not found: $base_sof" >&2
    exit 1
fi

if [[ ! -f $spl_hex ]]; then
    echo "HPS SPL HEX not found: $spl_hex" >&2
    echo "Pass Terasic's u-boot-spl-dtb.hex as the first argument." >&2
    exit 1
fi

ssh "$remote" "mkdir -p '$remote_stage'"
rsync -az "$base_sof" "$spl_hex" "$remote:$remote_stage/"

ssh "$remote" "docker run --rm --privileged --network host \
    -v /dev/bus/usb:/dev/bus/usb \
    -v '$remote_stage:/work' \
    -w /work \
    '$image' sh -lc \"quartus_pfg \
        -c DE25_PC110_PORT.sof $phase_prefix.rbf \
        -o hps_path=$(basename "$spl_hex") -o hps=1 && \
        test -s $phase_prefix.hps.rbf && \
        test -s $phase_prefix.core.rbf && \
        jtagconfig && \
        quartus_pgm -m jtag \
        -o 'p;$phase_prefix.hps.rbf@$device_index'\""

rsync -az \
    "$remote:$remote_stage/$phase_prefix.hps.rbf" \
    "$remote:$remote_stage/$phase_prefix.core.rbf" \
    "$repo_root/de25-nano/artifacts/"
sha256sum "$phase1_rbf" "$phase2_rbf" 2>/dev/null || \
    shasum -a 256 "$phase1_rbf" "$phase2_rbf"
echo "Phase 1 is running. Load the matching phase-2 core RBF from Linux."
