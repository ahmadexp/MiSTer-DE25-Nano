#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/cores/InputTest"}

# The Quartus container intentionally has no Git. Its outer host invocation
# applies the patches before mounting the workspace; verify that state on the
# recursive in-container invocation instead of failing on a missing tool.
if ! command -v git >/dev/null 2>&1; then
    if grep -q 'wire \[127:0\] status_bus;' "$source_dir/InputTest.sv" &&
       grep -q 'DE25_AGILEX' "$source_dir/rtl/dpram.v" &&
       grep -q 'HQ_TABLE' "$source_dir/sys/hq2x.sv"; then
        exit 0
    fi
    echo "InputTest compatibility patches must be applied before entering the Quartus container" >&2
    exit 1
fi

for patch_file in "$root_dir"/patches/InputTest/*.patch; do
    if git -C "$source_dir" apply --reverse --check --ignore-whitespace "$patch_file" 2>/dev/null; then
        continue
    fi
    git -C "$source_dir" apply --check --ignore-whitespace "$patch_file"
    git -C "$source_dir" apply --ignore-whitespace "$patch_file"
done
