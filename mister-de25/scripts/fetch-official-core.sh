#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF' >&2
Usage: fetch-official-core.sh HOME [DESTINATION]

Fetches one core from the locked official MiSTer catalog into a deterministic
source_id directory. Existing checkouts are fast-forwarded only; local changes
are never reset or overwritten.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 2
fi

home=$1
platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
catalog=${DE25_OFFICIAL_CATALOG:-$platform_root/official-core-catalog.tsv}
destination_root=${2:-$platform_root/upstream/official}

if [[ ! -f $catalog ]]; then
    echo "Official core catalog not found: $catalog" >&2
    exit 1
fi

record=$(awk -F '\t' -v wanted="$home" '
    NR > 1 && $3 == wanted {
        print $5 "\034" $6 "\034" $7
        found = 1
        exit
    }
    END { if (!found) exit 1 }
' "$catalog") || {
    echo "Official core home not found: $home" >&2
    exit 1
}
IFS=$'\034' read -r repository branch source_id <<<"$record"
if [[ -z $repository || -z $source_id || ! $source_id =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "Invalid locked source identity for: $home" >&2
    exit 1
fi

destination=$destination_root/$source_id
mkdir -p "$destination_root"
if [[ -d $destination/.git ]]; then
    if [[ -n $(git -C "$destination" status --porcelain) ]]; then
        echo "Refusing to update a modified core checkout: $destination" >&2
        exit 1
    fi
    fetch_args=(fetch --depth 1 origin)
    [[ -z $branch ]] || fetch_args+=("$branch")
    git -C "$destination" "${fetch_args[@]}"
    git -C "$destination" merge --ff-only FETCH_HEAD
elif [[ -e $destination ]]; then
    echo "Destination exists but is not a Git checkout: $destination" >&2
    exit 1
else
    clone_args=(clone --depth 1)
    [[ -z $branch ]] || clone_args+=(--branch "$branch")
    git "${clone_args[@]}" "$repository" "$destination"
fi

printf '%s\t%s\t%s\n' "$home" "$source_id" \
    "$(git -C "$destination" rev-parse HEAD)"
