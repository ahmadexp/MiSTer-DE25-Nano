#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ! $1 =~ ^[0-9]+$ ]]; then
    echo "Usage: build-menu-after-pid.sh PID STAGING_DIRECTORY" >&2
    exit 2
fi

catalog_pid=$1
staging=$2
platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for source in \
    "$staging/rtl/de25_mister_gp_bridge.sv" \
    "$staging/rtl/de25_mister_menu_top.sv" \
    "$staging/scripts/build-menu.sh"; do
    if [[ ! -s $source ]]; then
        echo "Staged Menu input is missing: $source" >&2
        exit 1
    fi
done

while kill -0 "$catalog_pid" 2>/dev/null; do
    sleep 15
done

install -m 0644 "$staging/rtl/de25_mister_gp_bridge.sv" \
    "$platform_root/rtl/de25_mister_gp_bridge.sv"
install -m 0644 "$staging/rtl/de25_mister_menu_top.sv" \
    "$platform_root/rtl/de25_mister_menu_top.sv"
install -m 0755 "$staging/scripts/build-menu.sh" \
    "$platform_root/scripts/build-menu.sh"

exec "$platform_root/scripts/build-menu.sh"
