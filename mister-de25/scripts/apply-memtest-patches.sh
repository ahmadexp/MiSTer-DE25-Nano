#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/cores/MemTest"}

if ! command -v git >/dev/null 2>&1; then
    if grep -q 'DE25_AGILEX_PLL_RECONFIG' "$source_dir/memtest.sv" &&
       grep -q 'DRAM_DQ_OE' "$source_dir/rtl/sdram.v"; then
        exit 0
    fi
    echo "MemTest compatibility patches must be applied before entering the Quartus container" >&2
    exit 1
fi

# A checkout with the latest cumulative patch already applied is complete.
# Later patches can deliberately replace lines introduced by earlier ones, so
# checking the latest patch first is required for idempotent rebuilds.
latest_patch=$(find "$root_dir/patches/MemTest" -name '*.patch' -type f | sort | tail -1)
if [[ -n "$latest_patch" ]] && \
   git -C "$source_dir" apply --reverse --check --ignore-whitespace \
       "$latest_patch" 2>/dev/null; then
    exit 0
fi

for patch_file in "$root_dir"/patches/MemTest/*.patch; do
    if git -C "$source_dir" apply --reverse --check --ignore-whitespace "$patch_file" 2>/dev/null; then
        continue
    fi
    git -C "$source_dir" apply --check --ignore-whitespace "$patch_file"
    git -C "$source_dir" apply --ignore-whitespace "$patch_file"
done
