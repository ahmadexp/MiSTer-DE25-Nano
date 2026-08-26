#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: quartus-syn-de25.sh PROJECT [REVISION]" >&2
    exit 2
fi

project=$1
revision=${2:-$project}
quartus_syn_args=("$project" -c "$revision")

if [[ ${DE25_HPS_RESET_V1_RECOVERY:-0} == 1 ]]; then
    quartus_syn_args+=(--set=VERILOG_MACRO=DE25_HPS_RESET_V1_RECOVERY)
elif [[ ${DE25_HPS_RESET_RECOVERY:-0} == 1 ]]; then
    quartus_syn_args+=(--set=VERILOG_MACRO=DE25_HPS_RESET_RECOVERY)
elif [[ ${DE25_HPS_RESET_V1_REPRO:-0} == 1 ]]; then
    quartus_syn_args+=(--set=VERILOG_MACRO=DE25_HPS_RESET_V1_REPRO)
fi

exec quartus_syn "${quartus_syn_args[@]}"
