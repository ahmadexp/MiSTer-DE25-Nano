#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
target_root="$repo_root/de25-nano"
remote=${DE25_BUILD_HOST:-user@192.168.1.18}
remote_root=${DE25_REMOTE_ROOT:-PC110-Mister-de25}

if [[ ! -f "$target_root/vendor/terasic-ghrd/qsys_top.qsys" ]]; then
    echo "Terasic GHRD sources are missing." >&2
    echo "Run de25-nano/scripts/import-terasic-ghrd.sh first." >&2
    exit 1
fi

ssh "$remote" "mkdir -p '$remote_root/de25-nano' '$remote_root/rtl'"
rsync -az --delete "$repo_root/rtl/" "$remote:$remote_root/rtl/"
rsync -az --delete \
    --exclude artifacts \
    --exclude ip/ip \
    --exclude ip/pc110_pll \
    --exclude ip/pc110_pll.qsys \
    --exclude vendor/terasic-ghrd/pc110_hps \
    --exclude vendor/terasic-ghrd/pc110_hps.qsys \
    --exclude vendor/terasic-ghrd/hps_subsys/hps_subsys \
    --exclude vendor/terasic-ghrd/jtag_subsys/jtag_subsys \
    --exclude vendor/terasic-ghrd/peripheral_subsys/peripheral_subsys \
    --exclude quartus/db \
    --exclude quartus/dni \
    --exclude quartus/incremental_db \
    --exclude 'quartus/output_files*' \
    --exclude quartus/qdb \
    "$target_root/" "$remote:$remote_root/de25-nano/"

ssh -t "$remote" "cd '$remote_root/de25-nano' && chmod +x scripts/*.sh && scripts/build-port.sh"

mkdir -p "$target_root/artifacts"
rsync -az \
    "$remote:$remote_root/de25-nano/quartus/output_files_port/DE25_PC110_PORT.sof" \
    "$target_root/artifacts/"

rsync -az \
    "$remote:$remote_root/de25-nano/quartus/output_files_port/DE25_PC110_PORT.fit.rpt" \
    "$remote:$remote_root/de25-nano/quartus/output_files_port/DE25_PC110_PORT.sta.rpt" \
    "$target_root/artifacts/"
