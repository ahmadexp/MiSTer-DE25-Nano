#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
cores_dir=${1:-"$root_dir/upstream/cores"}

printf 'core\temu\thps_bus\tinterface\tcyclone_files\tddram\tsdram\tstatus\n'

for core_dir in "$cores_dir"/*; do
  [[ -d "$core_dir" ]] || continue
  name=${core_dir##*/}
  # Prefer the core's root-level emu over simulator and testbench wrappers.
  emu=$(rg -l 'module[[:space:]]+emu' "$core_dir" -g '*.{sv,v}' \
    -g '!verilator/**' -g '!sim/**' -g '!simulation/**' -g '!testbench/**' \
    | awk -v root="$core_dir/" '{ rel=$0; sub("^" root, "", rel); print (rel ~ /\//), length(rel), $0 }' \
    | sort -n -k1,1 -k2,2 | awk 'NR == 1 { print $3 }' || true)
  hps_bus=$(rg 'inout[[:space:]]+\[[0-9]+:0\][[:space:]]+HPS_BUS' "$core_dir" -g '*.{sv,v,vh}' | head -1 | sed -E 's/.*\[([0-9]+):0\].*/\1/' || true)
  cyclone_files=$(rg -l 'cyclonev_|Cyclone V|CYCLONEV' "$core_dir" -g '*.{sv,v,vhd,qsf,qip}' | wc -l | tr -d ' ')
  ddram=$(rg -l 'DDRAM_(CLK|ADDR|RD|WE)' "$core_dir" -g '*.{sv,v,vh}' | head -1 || true)
  sdram=$(rg -l 'SDRAM_(CLK|A|DQ|nCS)' "$core_dir" -g '*.{sv,v,vh}' | head -1 || true)
  interface=unknown
  status=ready-for-overlay

  [[ -n "$emu" ]] || status=no-emu-top
  case "$hps_bus" in
    45) interface=legacy-46 ;;
    48) interface=extended-49 ;;
    *) status="hps-bus-${hps_bus:-unknown}" ;;
  esac

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "${emu#"$core_dir/"}" "${hps_bus:-unknown}" "$interface" "$cyclone_files" \
    "$([[ -n "$ddram" ]] && echo yes || echo no)" \
    "$([[ -n "$sdram" ]] && echo yes || echo no)" "$status"
done
