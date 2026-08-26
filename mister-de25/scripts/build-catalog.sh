#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
matrix=${DE25_BUILD_MATRIX:-$platform_root/build-matrix.tsv}

usage() {
    cat <<'EOF'
Usage: build-catalog.sh --list
       build-catalog.sh --supported
       build-catalog.sh --registered
       build-catalog.sh --core HOME

Lists or builds DE25-supported entries from the generated official-core
matrix. Repositories shared by several installed variants are represented by
separate HOME rows, but a build is dispatched only for an explicit DE25 port.
`--supported` preserves the release set, while `--registered` also rebuilds
ports that are still awaiting packaging or hardware qualification.
EOF
}

if [[ ! -f $matrix ]]; then
    echo "Build matrix is missing; run scripts/refresh-build-matrix.sh" >&2
    exit 1
fi
if [[ $# -lt 1 ]]; then
    usage >&2
    exit 2
fi

list_supported() {
    awk -F '\t' 'NR == 1 || $8 == "packaged" {print}' "$matrix"
}

build_home() {
    local wanted=$1
    local record name status build_script
    record=$(awk -F '\t' -v wanted="$wanted" '
        NR > 1 && $3 == wanted {
            printf "%s\034%s\034%s", $2, $8, $9
            found = 1
            exit
        }
        END { if (!found) exit 1 }
    ' "$matrix") || {
        echo "Unknown core home: $wanted" >&2
        exit 1
    }
    IFS=$'\034' read -r name status build_script <<<"$record"
    if [[ -z $build_script ]]; then
        echo "Core has no registered DE25-Nano build: $wanted ($status)" >&2
        exit 1
    fi
    echo "Building $name ($wanted) with $build_script"
    "$platform_root/$build_script"
}

case $1 in
    --list)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        list_supported
        ;;
    --supported)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        while IFS= read -r build_script; do
            echo "Building supported catalog entry with $build_script"
            "$platform_root/$build_script"
        done < <(awk -F '\t' '
            NR > 1 && $8 == "packaged" && $9 != "" && !seen[$9]++ { print $9 }
        ' "$matrix")
        ;;
    --registered)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        while IFS= read -r build_script; do
            echo "Building registered DE25 catalog entry with $build_script"
            "$platform_root/$build_script"
        done < <(awk -F '\t' '
            NR > 1 && $9 != "" && !seen[$9]++ { print $9 }
        ' "$matrix")
        ;;
    --core)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        build_home "$2"
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
