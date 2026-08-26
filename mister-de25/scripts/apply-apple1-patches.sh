#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/cores/Apple-I"}

if ! command -v git >/dev/null 2>&1; then
    if grep -q 'wire \[127:0\] status_bus;' \
            "$source_dir/boards/MiSTer/Apple-I.sv" &&
       grep -q 'ROM_DEPTH' "$source_dir/boards/MiSTer/sys/hps_io.sv"; then
        exit 0
    fi
    echo "Apple-I compatibility patches must be applied before entering the Quartus container" >&2
    exit 1
fi

for patch_file in "$root_dir"/patches/Apple-I/*.patch; do
    if git -C "$source_dir" apply --reverse --check --ignore-whitespace \
            "$patch_file" 2>/dev/null; then
        continue
    fi
    git -C "$source_dir" apply --check --ignore-whitespace "$patch_file"
    git -C "$source_dir" apply --ignore-whitespace "$patch_file"
done
