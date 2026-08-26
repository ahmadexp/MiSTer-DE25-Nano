#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/cores/TurboGrafx16"}
latest_patch=$(find "$root_dir/patches/TurboGrafx16" -name '*.patch' -type f 2>/dev/null | sort | tail -1)

if [[ -z $latest_patch ]]; then
    echo "No TurboGrafx16 compatibility patch found" >&2
    exit 1
fi

# A reverse check proves the complete compatibility patch is present. Avoid a
# small sentinel set here because an interrupted or older partial port can
# otherwise be mistaken for a fully patched source tree.
if git -C "$source_dir" apply --reverse --check --ignore-whitespace \
    "$latest_patch" 2>/dev/null; then
    exit 0
fi
git -C "$source_dir" apply --check --ignore-whitespace "$latest_patch"
git -C "$source_dir" apply --ignore-whitespace "$latest_patch"
