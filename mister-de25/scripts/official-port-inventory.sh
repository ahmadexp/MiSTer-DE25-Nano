#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
catalog=$platform_root/official-core-catalog.tsv
source_root=${1:-$platform_root/upstream/official}

printf 'category\tname\thome\tsource_id\tfetched\temu\thps_bus\tinterface\tcyclone_files\tddram\tsdram\tstatus\n'
while IFS=$'\034' read -r category name home source_id; do
    source=$source_root/$source_id
    if [[ ! -d $source ]]; then
        printf '%s\t%s\t%s\t%s\tno\t\t\t\t\t\t\tnot-fetched\n' \
            "$category" "$name" "$home" "$source_id"
        continue
    fi

    emu=$(rg -l 'module[[:space:]]+emu' "$source" -g '*.{sv,v}' \
        -g '!verilator/**' -g '!sim/**' -g '!simulation/**' -g '!testbench/**' \
        | awk -v root="$source/" '{ rel=$0; sub("^" root, "", rel); print (rel ~ /\//), length(rel), rel }' \
        | sort -n -k1,1 -k2,2 | awk 'NR == 1 { print $3 }' || true)
    hps_bus=$(rg 'inout[[:space:]]+(wire[[:space:]]+)?\[[0-9]+:0\][[:space:]]+HPS_BUS' \
        "$source" -g '*.{sv,v,vh}' | head -1 | \
        sed -E 's/.*\[([0-9]+):0\].*/\1/' || true)
    cyclone_files=$(rg -l 'cyclonev_|Cyclone V|CYCLONEV' "$source" \
        -g '*.{sv,v,vhd,qsf,qip}' | wc -l | tr -d ' ')
    ddram=$(rg -l 'DDRAM_(CLK|ADDR|RD|WE)' "$source" \
        -g '*.{sv,v,vh}' | head -1 || true)
    native_sdram=$(rg -l 'SDRAM_(CLK|A|DQ|nCS)' "$source" \
        -g '*.{sv,v,vh}' | head -1 || true)
    interface=unknown
    status=ready-for-overlay
    [[ -n $emu ]] || status=no-emu-top
    case $hps_bus in
        45) interface=legacy-46 ;;
        48) interface=extended-49 ;;
        *) status="hps-bus-${hps_bus:-unknown}" ;;
    esac
    printf '%s\t%s\t%s\t%s\tyes\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$category" "$name" "$home" "$source_id" "$emu" \
        "${hps_bus:-unknown}" "$interface" "$cyclone_files" \
        "$([[ -n $ddram ]] && echo yes || echo no)" \
        "$([[ -n $native_sdram ]] && echo yes || echo no)" "$status"
done < <(awk -F '\t' 'NR > 1 { print $1 "\034" $2 "\034" $3 "\034" $7 }' \
    "$catalog")
