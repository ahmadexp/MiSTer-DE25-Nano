#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
lock_file=${DE25_MAIN_LOCK:-$platform_root/upstream-main.lock}
destination=${1:-$platform_root/upstream/Main_MiSTer}

record=$(awk -F '\t' 'NR == 2 { print $1 "\034" $2; exit }' "$lock_file")
IFS=$'\034' read -r repository revision <<<"$record"

if [[ -z $repository || ! $revision =~ ^[0-9a-f]{40}$ ]]; then
    echo "Invalid Main_MiSTer lock: $lock_file" >&2
    exit 1
fi

if [[ -d $destination/.git ]]; then
    if git -C "$destination" apply --reverse --check \
        "$platform_root/patches/Main_MiSTer/9999-de25-complete.patch" \
        >/dev/null 2>&1; then
        printf 'Main_MiSTer is already prepared at %s\n' "$revision"
        exit 0
    fi
    if [[ -n $(git -C "$destination" status --porcelain) ]]; then
        echo "Refusing to replace a modified Main_MiSTer checkout: $destination" >&2
        exit 1
    fi
    git -C "$destination" fetch --depth 1 origin "$revision"
else
    mkdir -p "$destination"
    git -C "$destination" init -q
    git -C "$destination" remote add origin "$repository"
    git -C "$destination" fetch --depth 1 origin "$revision"
fi

git -C "$destination" checkout -q --detach FETCH_HEAD
if [[ $(git -C "$destination" rev-parse HEAD) != "$revision" ]]; then
    echo "Main_MiSTer revision mismatch" >&2
    exit 1
fi

"$platform_root/scripts/apply-main-patches.sh" "$destination"
printf 'Prepared Main_MiSTer at %s\n' "$revision"
