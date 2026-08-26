#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
system_name=${1:-memtest_core_pll_cal}
ip_root="$platform_root/ip/ip/$system_name"

if [[ $# -ge 2 ]]; then
    cal_roots=(
        "$ip_root/$2/emif_ph2_cal_arch_fp_420/synth"
    )
else
    shopt -s nullglob
    cal_roots=(
        "$ip_root"/${system_name}_cal_*/emif_ph2_cal_arch_fp_420/synth
    )
    shopt -u nullglob
fi

if [[ ${#cal_roots[@]} -eq 0 ]]; then
    echo "No generated IOSSM calibration component found under $ip_root" >&2
    exit 1
fi

# Quartus Pro 25.3.1 emits a placeholder and omits this mandatory hard-IP
# parameter for a standalone Calibration IP. Its HPS instance uses an empty
# parameter-table filename, which is also correct for a standalone IOPLL.
for cal_root in "${cal_roots[@]}"; do
    mapfile -t attribute_files < <(find "$cal_root" -maxdepth 1 -name '*_atom_attr_iossm.sv' -type f)
    mapfile -t instance_files < <(find "$cal_root" -maxdepth 1 -name '*_cal_arch_fp_atom_inst_iossm.sv' -type f)

    if [[ ${#attribute_files[@]} -ne 1 || ${#instance_files[@]} -ne 1 ]]; then
        echo "Expected one IOSSM attribute file and one IOSSM instance file under $cal_root" >&2
        exit 1
    fi

    attribute_file=${attribute_files[0]}
    instance_file=${instance_files[0]}
    sed -i 's/= "path\/to\/file.hex";/= "";/' "$attribute_file"

    if ! grep -q '\.parameter_table_hexfile' "$instance_file"; then
        sed -i '/\.iossm_mem_init_0[[:space:]]*(IOSSM_MEM_INIT_LOWER\[0\])/s/)/),/' "$instance_file"
        sed -i '/\.iossm_mem_init_0[[:space:]]*(IOSSM_MEM_INIT_LOWER\[0\]),/a\      .parameter_table_hexfile                              (PARAMETER_TABLE_HEXFILE)' "$instance_file"
    fi

    grep -q 'PARAMETER_TABLE_HEXFILE[[:space:]]*= "";' "$attribute_file"
    grep -q '\.parameter_table_hexfile[[:space:]]*(PARAMETER_TABLE_HEXFILE)' "$instance_file"
done

echo "Applied Quartus 25.3.1 standalone EMIF Calibration IP workaround to ${#cal_roots[@]} component(s)"
