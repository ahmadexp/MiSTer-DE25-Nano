#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
wiki_repository=https://github.com/MiSTer-devel/Wiki_MiSTer.wiki.git
if [[ $# -gt 1 ]]; then
    echo "Usage: refresh-build-matrix.sh [CORES.md]" >&2
    exit 2
fi

source_path=
source_label=
source_revision=local
work_dir=
cleanup() {
    [[ -z $work_dir ]] || rm -rf -- "$work_dir"
}
trap cleanup EXIT

if [[ $# -eq 1 ]]; then
    source_path=$1
    source_label=$1
else
    if ! command -v git >/dev/null 2>&1; then
        echo "git is required to lock the official Wiki revision" >&2
        exit 1
    fi
    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/de25-core-catalog.XXXXXXXX")
    git clone --quiet --depth 1 "$wiki_repository" "$work_dir/wiki"
    source_path=$work_dir/wiki/Cores.md
    source_label=$wiki_repository
    source_revision=$(git -C "$work_dir/wiki" rev-parse HEAD)
fi

python3 "$platform_root/scripts/refresh-official-catalog.py" \
    --source "$source_path" \
    --source-label "$source_label" \
    --source-revision "$source_revision" \
    --output "$platform_root/official-core-catalog.tsv" \
    --lock-output "$platform_root/official-core-catalog.lock"
python3 "$platform_root/scripts/generate-build-matrix.py" \
    --catalog "$platform_root/official-core-catalog.tsv" \
    --additional-catalog "$platform_root/local-core-catalog.tsv" \
    --status "$platform_root/port-status.tsv" \
    --output "$platform_root/build-matrix.tsv"
