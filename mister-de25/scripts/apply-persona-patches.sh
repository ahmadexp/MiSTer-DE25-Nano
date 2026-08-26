#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: apply-persona-patches.sh SOURCE_DIR PATCH_DIR" >&2
    exit 2
fi

source_dir=$(cd "$1" && pwd)
patch_dir=$(cd "$2" && pwd)

[[ -d $source_dir/.git ]] || {
    echo "Persona source is not a Git checkout: $source_dir" >&2
    exit 1
}
[[ -d $patch_dir ]] || {
    echo "Persona patch directory is missing: $patch_dir" >&2
    exit 1
}

shopt -s nullglob
patches=("$patch_dir"/*.patch)
[[ ${#patches[@]} -gt 0 ]] || {
    echo "No persona patches found in: $patch_dir" >&2
    exit 1
}

# A later patch may intentionally edit lines introduced by an earlier patch.
# In that case `git apply --reverse --check` can no longer recognize the
# earlier patch on a subsequent build. Record the exact ordered patch series
# inside Git's private metadata after the first successful application.
hash_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    else
        shasum -a 256 "$@"
    fi
}
series_id=$(hash_stream "${patches[@]}" | hash_stream | awk '{print $1}')
git_dir=$(git -C "$source_dir" rev-parse --absolute-git-dir)
stamp_dir=$git_dir/de25-persona-patches
stamp_file=$stamp_dir/$series_id
if [[ -f $stamp_file ]]; then
    exit 0
fi

# When a patch series is extended, the source may already contain a stamped
# prefix. Resume with the first new patch. This avoids trying to reverse-check
# an older patch after a later patch intentionally edited one of its lines.
applied_prefix=0
for ((prefix_count=${#patches[@]}; prefix_count > 0; prefix_count--)); do
    prefix_id=$(hash_stream "${patches[@]:0:prefix_count}" | hash_stream | awk '{print $1}')
    if [[ -f $stamp_dir/$prefix_id ]]; then
        applied_prefix=$prefix_count
        break
    fi
done

for ((patch_index=applied_prefix; patch_index<${#patches[@]}; patch_index++)); do
    patch_file=${patches[$patch_index]}
    if git -C "$source_dir" apply --reverse --check --recount --ignore-whitespace \
            "$patch_file" 2>/dev/null; then
        continue
    fi
    git -C "$source_dir" apply --check --recount --ignore-whitespace "$patch_file"
    git -C "$source_dir" apply --recount --ignore-whitespace "$patch_file"
done

mkdir -p "$stamp_dir"
printf '%s\n' "$series_id" >"$stamp_file"
