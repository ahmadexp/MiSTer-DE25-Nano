#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! $1 =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "Usage: prepare-ghrd-worktree.sh BUILD_ID" >&2
    exit 2
fi

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$platform_root/.." && pwd)
source_root=${DE25_GHRD_SOURCE_ROOT:-$workspace_root/de25-nano/vendor/terasic-ghrd}
baseline_root=${DE25_GHRD_BASELINE_ROOT:-$workspace_root/de25-nano/vendor/terasic-ghrd-pristine}
# Quartus project files use this fixed relative location. Refresh that location
# atomically from a separate immutable baseline before each build. Catalog
# builds are deliberately serialized because Quartus also shares project output
# directories and generated PLL IP between cores.
work_root=$source_root
staging_root=$source_root.new.$$

source_hps_ip=$source_root/hps_subsys/ip/hps_subsys/agilex_hps.ip
baseline_hps_ip=$baseline_root/hps_subsys/ip/hps_subsys/agilex_hps.ip
source_version=9.0.0

if [[ ! -d $baseline_root ]]; then
    if [[ ! -s $source_hps_ip ]] ||
       ! grep -q "<ipxact:version>${source_version//./\\.}</ipxact:version>" "$source_hps_ip"; then
        echo "The immutable Terasic GHRD baseline is missing, and the source tree has already been upgraded." >&2
        echo "Restore the original Quartus 25.1 DE25-Nano GHRD at: $source_root" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$baseline_root")"
    baseline_staging=$baseline_root.new.$$
    rm -rf "$baseline_staging"
    cp -a "$source_root" "$baseline_staging"
    mv "$baseline_staging" "$baseline_root"
fi

if [[ ! -s $baseline_hps_ip ]] ||
   ! grep -q "<ipxact:version>${source_version//./\\.}</ipxact:version>" "$baseline_hps_ip"; then
    echo "Terasic GHRD baseline is not the original Quartus 25.1 revision: $baseline_root" >&2
    exit 1
fi

rm -rf "$staging_root"
cp -a "$baseline_root" "$staging_root"
rm -rf "$work_root"
mv "$staging_root" "$work_root"

printf '%s\n' "$work_root"
