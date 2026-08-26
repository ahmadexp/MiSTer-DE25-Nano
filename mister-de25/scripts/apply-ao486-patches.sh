#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/cores/AO486"}

patches=()
while IFS= read -r patch; do
    patches+=("$patch")
done < <(find "$root_dir/patches/AO486" -name '*.patch' -type f 2>/dev/null | sort)
if [[ ${#patches[@]} -eq 0 ]]; then
    echo "No ao486 compatibility patch found" >&2
    exit 1
fi

# A later patch may intentionally edit context introduced by an earlier one.
# In that fully-applied state, reversing the older patch alone can fail even
# though the complete ordered series is present. The final patch is defined to
# depend on the preceding series, so its reversibility is the idempotent fast
# path for an already-prepared source tree.
latest_patch=${patches[${#patches[@]}-1]}
if git -C "$source_dir" apply --reverse --check --ignore-whitespace \
    "$latest_patch" >/dev/null 2>&1; then
    exit 0
fi

for patch in "${patches[@]}"; do
    if git -C "$source_dir" apply --reverse --check --ignore-whitespace "$patch" >/dev/null 2>&1; then
        continue
    fi

    git -C "$source_dir" apply --check --ignore-whitespace "$patch"
    git -C "$source_dir" apply --ignore-whitespace "$patch"
done
