#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/Main_MiSTer"}
complete_patch=$root_dir/patches/Main_MiSTer/9999-de25-complete.patch

# The numbered patches retain the development history. Some intentionally
# overlap earlier changes, so a clean checkout is prepared from the consolidated
# patch generated from the hardware-validated source tree.
if git -C "$source_dir" apply --reverse --check --ignore-whitespace \
    "$complete_patch" 2>/dev/null; then
  exit 0
fi

git -C "$source_dir" apply --check --ignore-whitespace "$complete_patch"
git -C "$source_dir" apply --ignore-whitespace "$complete_patch"
