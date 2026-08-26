#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/cores/SMS"}
latest_patch=$(find "$root_dir/patches/SMS" -name '*.patch' -type f 2>/dev/null | sort | tail -1)

if [[ -z $latest_patch ]]; then
    echo "No SMS compatibility patch found" >&2
    exit 1
fi

# A reverse check proves that every clock, quiesce, and split-DQ change is
# present. A few marker greps are not sufficient for an SDRAM safety patch.
if git -C "$source_dir" apply --reverse --check --ignore-whitespace \
    "$latest_patch" 2>/dev/null; then
    exit 0
fi
git -C "$source_dir" apply --check --ignore-whitespace "$latest_patch"
git -C "$source_dir" apply --ignore-whitespace "$latest_patch"
