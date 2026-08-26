#!/usr/bin/env bash
set -euo pipefail

target_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
remote=${DE25_BUILD_HOST:-user@192.168.1.18}
remote_root=${DE25_REMOTE_ROOT:-PC110-Mister-de25}

ssh "$remote" "mkdir -p '$remote_root/de25-nano'"
rsync -az --delete \
    --exclude quartus/db \
    --exclude quartus/dni \
    --exclude quartus/incremental_db \
    --exclude quartus/output_files \
    --exclude quartus/qdb \
    "$target_root/" "$remote:$remote_root/de25-nano/"

ssh -t "$remote" "cd '$remote_root/de25-nano' && chmod +x scripts/*.sh && scripts/build.sh"

mkdir -p "$target_root/artifacts"
rsync -az \
    "$remote:$remote_root/de25-nano/quartus/output_files/DE25_PC110_DIAG.sof" \
    "$target_root/artifacts/"
