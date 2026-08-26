#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/cores/Minimig"}
latest_patch=$(find "$root_dir/patches/Minimig" -name '*.patch' -type f 2>/dev/null | sort | tail -1)

if grep -q 'DE25_AGILEX_PLL_RECONFIG' "$source_dir/Minimig.sv" &&
   grep -q 'sd_data_oe' "$source_dir/rtl/sdram_ctrl.v" &&
   grep -q 'de25_sdram_dq_oe' "$source_dir/sys/emu_ports.vh"; then
    exit 0
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Minimig compatibility patch must be applied before entering Quartus" >&2
    exit 1
fi

if [[ -z "$latest_patch" ]]; then
    echo "No Minimig compatibility patch found" >&2
    exit 1
fi

if git -C "$source_dir" apply --reverse --check --ignore-whitespace \
    "$latest_patch" 2>/dev/null; then
    exit 0
fi

for patch_file in "$root_dir"/patches/Minimig/*.patch; do
    if git -C "$source_dir" apply --reverse --check --ignore-whitespace \
        "$patch_file" 2>/dev/null; then
        continue
    fi
    git -C "$source_dir" apply --check --ignore-whitespace "$patch_file"
    git -C "$source_dir" apply --ignore-whitespace "$patch_file"
done
