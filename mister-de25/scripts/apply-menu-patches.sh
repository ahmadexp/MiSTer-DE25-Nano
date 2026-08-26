#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/cores/Menu"}

# A checkout with the latest patch already applied is necessarily complete.
# Check it first because later patches can deliberately supersede lines added
# by earlier compatibility patches.
latest_patch=$(find "$root_dir/patches/Menu" -name '*.patch' -type f | sort | tail -1)
if [[ -n "$latest_patch" ]] && \
   git -C "$source_dir" apply --reverse --check --ignore-whitespace "$latest_patch" 2>/dev/null; then
    exit 0
fi

for patch_file in "$root_dir"/patches/Menu/*.patch; do
    # Menu sources use CRLF. Ignore whitespace while checking so patches remain
    # idempotent regardless of the checkout's line-ending normalization.
    if git -C "$source_dir" apply --reverse --check --ignore-whitespace "$patch_file" 2>/dev/null; then
        continue
    fi
    git -C "$source_dir" apply --check --ignore-whitespace "$patch_file"
    git -C "$source_dir" apply --ignore-whitespace "$patch_file"
done
