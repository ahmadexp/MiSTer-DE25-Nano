#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export DE25_PERSONA_PROJECT=DE25_MISTER_N64_V2
export DE25_PERSONA_SOURCE_ID=MiSTer-devel_N64_MiSTer
export DE25_PERSONA_PATCH_DIR=N64
export DE25_PERSONA_PLL_NAME=n64_core_pll
export DE25_PERSONA_PLL_SCRIPT=create_n64_core_pll.tcl
export DE25_PERSONA_EXTRA_PLL_NAME=n64_video_pll
export DE25_PERSONA_EXTRA_PLL_SCRIPT=create_n64_video_pll.tcl
export DE25_PERSONA_OUTPUT_DIRECTORY=output_files_n64_v2
export DE25_PERSONA_OUTPUT_RBF="$platform_root/artifacts/n64-v2/N64_v2_ntsc_bringup.rbf"
export DE25_HPS_PARTITION_MODE=reuse
export DE25_HPS_PARTITION_QDB="$platform_root/artifacts/menu-v2/de25_mister_hps_fdcd_synth.qdb"
export DE25_EXPECTED_HPS_IO_HASH_FILE="$platform_root/platforms/fdcd.hps-io-hash"

exec "$platform_root/scripts/build-simple-persona.sh"
