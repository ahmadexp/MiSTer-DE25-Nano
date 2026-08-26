#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

export DE25_MENU_PROJECT=DE25_MISTER_MENU_V2
export DE25_MENU_OUTPUT_DIRECTORY=output_files_menu_v2
export DE25_MENU_OUTPUT_RBF="$platform_root/artifacts/menu-v2/menu_v2.rbf"
export DE25_MENU_ARTIFACT_PREFIX="$platform_root/artifacts/menu-v2/DE25_MISTER_MENU_V2_HPS_FIRST"
# Platform v2 uses the already validated FDCD synthesized HPS partition.
# Rebuilding the fabric while preserving that hard-HPS netlist keeps the HPS
# ABI stable and avoids Quartus 25.3.1 upgrading the Quartus 25.1 HPS schema.
export DE25_HPS_PARTITION_MODE=reuse
export DE25_HPS_PARTITION_QDB="$platform_root/artifacts/menu-v2/de25_mister_hps_fdcd_synth.qdb"
export DE25_EXPECTED_HPS_IO_HASH_FILE="$platform_root/platforms/fdcd.hps-io-hash"
# The current build host has 15 GB RAM. Parallel Platform Designer generation
# can launch six 6 GB Java workers and disconnect its own service under memory
# pressure, so serialize IP generation for a deterministic clean build.
export DE25_IPGEN_PARALLEL=off

exec "$platform_root/scripts/build-menu.sh"
