#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

export DE25_AO486_PROJECT=DE25_MISTER_AO486_V2
export DE25_AO486_OUTPUT_DIRECTORY=output_files_ao486_v2
export DE25_AO486_OUTPUT_RBF="$platform_root/artifacts/ao486-v2/AO486_v2.rbf"
export DE25_HPS_PARTITION_MODE=reuse
export DE25_HPS_PARTITION_QDB="$platform_root/artifacts/menu-v2/de25_mister_hps_fdcd_synth.qdb"
export DE25_EXPECTED_HPS_IO_HASH_FILE="$platform_root/platforms/fdcd.hps-io-hash"

if [[ ! -f $DE25_HPS_PARTITION_QDB ]]; then
    echo "Platform V2 HPS partition not found: $DE25_HPS_PARTITION_QDB" >&2
    echo "Run scripts/build-menu-v2.sh first." >&2
    exit 1
fi

exec "$platform_root/scripts/build-ao486.sh"
