#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/cores/PCXT"}
latest_patch=$(find "$root_dir/patches/PCXT" -name '*.patch' -type f 2>/dev/null | sort | tail -1)

if [[ -z $latest_patch ]]; then
    echo "No PCXT compatibility patch found" >&2
    exit 1
fi

if git -C "$source_dir" apply --reverse --check --ignore-whitespace \
    "$latest_patch" 2>/dev/null; then
    exit 0
fi
git -C "$source_dir" apply --check --ignore-whitespace "$latest_patch"
git -C "$source_dir" apply --ignore-whitespace "$latest_patch"
