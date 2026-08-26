#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$platform_root/.." && pwd)
project=${DE25_AO486_PROJECT:-DE25_MISTER_AO486}
output_directory=${DE25_AO486_OUTPUT_DIRECTORY:-output_files_ao486}
output_rbf=${DE25_AO486_OUTPUT_RBF:-$platform_root/artifacts/ao486/AO486_20260815.rbf}
hps_bootloader=${DE25_HPS_BOOTLOADER:-$workspace_root/de25-nano/artifacts/u-boot-spl-dtb.hex}
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
quartus_home=${QUARTUS_HOME_DIR:-$HOME/quartus-pro-home}
host_uid=$(id -u)
host_gid=$(id -g)

if command -v git >/dev/null 2>&1; then
    "$platform_root/scripts/apply-ao486-patches.sh"
fi

generate_and_build() {
    source "$platform_root/scripts/acquire-ghrd-build-lock.sh"
    if [[ ! -f $hps_bootloader ]]; then
        echo "HPS bootloader not found: $hps_bootloader" >&2
        exit 1
    fi
    printf '`define BUILD_DATE "260815"\n' > \
        "$platform_root/upstream/cores/AO486/build_id.v"
    ghrd_root=$("$platform_root/scripts/prepare-ghrd-worktree.sh" "$project")
    cd "$platform_root/ip"
    rm -rf mister_pll ao486_core_pll_cal ao486_peripheral_pll \
        ip/mister_pll ip/ao486_core_pll_cal ip/ao486_peripheral_pll \
        "$ghrd_root/mister_hps" "$ghrd_root/ip/mister_hps"
    rm -f mister_pll.qsys ao486_core_pll_cal.qsys \
        ao486_peripheral_pll.qsys \
        "$ghrd_root/mister_hps.qsys"
    qsys-generate --upgrade-ip-cores \
        "$ghrd_root/hps_subsys/ip/hps_subsys/agilex_hps.ip"
    qsys-generate --upgrade-ip-cores \
        "$ghrd_root/peripheral_subsys/ip/peripheral_subsys/sysid.ip"
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_mister_pll.tcl
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_ao486_core_pll_cal.tcl
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_mister_hps.tcl
    cd "$platform_root/quartus"
    quartus_sh --clean -c "$project" "$project"
    quartus_ipgenerate "$project" -c "$project" --run_default_mode_op \
        --parallel=off
    "$platform_root/scripts/fix-emif-calibration-ip.sh" ao486_core_pll_cal
    "$platform_root/scripts/quartus-syn-de25.sh" "$project"
    if grep -Fq 'Output port "SDRAM_DQ_OUT[0..15]"' \
            "$output_directory/$project.syn.rpt"; then
        echo "ao486 synthesis removed the GUS SDRAM write datapath" >&2
        exit 1
    fi
    quartus_fit "$project" -c "$project"
    quartus_asm "$project" -c "$project"
    quartus_sta "$project" -c "$project"
    ../scripts/check-timing-summary.sh \
        "$output_directory/$project.sta.summary"
    quartus_sta -t ../scripts/report-sdram-timing.tcl "$project"
    "$platform_root/scripts/make-hps-first-rbf.sh" \
        "$output_directory/$project.sof" "$output_rbf" "$hps_bootloader"
}

if command -v quartus_sh >/dev/null 2>&1; then
    generate_and_build
    exit
fi

docker_args=(
    run --rm --network host --user "$host_uid:$host_gid"
    -e HOME=/quartus-home
    -v "$workspace_root:/work/PC110-Mister"
    -v "$quartus_home:/quartus-home"
    -w /work/PC110-Mister/mister-de25
)
if [[ -n ${DE25_QUARTUS_SYSFS_WORKAROUND_DIR:-} ]]; then
    sysfs_root=${DE25_QUARTUS_SYSFS_WORKAROUND_DIR%/}
    for sysfs_dir in block bus class dev devices; do
        if [[ ! -d $sysfs_root/$sysfs_dir ]]; then
            echo "Quartus sysfs workaround directory not found: $sysfs_root/$sysfs_dir" >&2
            exit 1
        fi
    done
    docker_args+=(
        -v "$sysfs_root/block:/sys/block:ro"
        -v "$sysfs_root/bus:/sys/bus:ro"
        -v "$sysfs_root/class:/sys/class:ro"
        -v "$sysfs_root/dev:/sys/dev:ro"
        -v "$sysfs_root/devices:/sys/devices:ro"
        -v /sys/class/net:/sys/class/net:ro
        -v /sys/class/dmi:/sys/class/dmi:ro
        -v /sys/devices/virtual/net:/sys/devices/virtual/net:ro
        -v /sys/devices/virtual/dmi:/sys/devices/virtual/dmi:ro
    )
fi
if [[ -n ${DE25_DOCKER_CPUSET:-} ]]; then
    docker_args+=( --cpuset-cpus "$DE25_DOCKER_CPUSET" )
fi
[[ -z ${LM_LICENSE_FILE:-} ]] || docker_args+=( -e "LM_LICENSE_FILE=$LM_LICENSE_FILE" )
[[ -z ${SALT_LICENSE_SERVER:-} ]] || docker_args+=( -e "SALT_LICENSE_SERVER=$SALT_LICENSE_SERVER" )
[[ -z ${DE25_AO486_PROJECT:-} ]] || docker_args+=( -e "DE25_AO486_PROJECT=$DE25_AO486_PROJECT" )
[[ -z ${DE25_AO486_OUTPUT_DIRECTORY:-} ]] || docker_args+=( -e "DE25_AO486_OUTPUT_DIRECTORY=$DE25_AO486_OUTPUT_DIRECTORY" )
[[ -z ${DE25_HPS_PARTITION_MODE:-} ]] || docker_args+=( -e "DE25_HPS_PARTITION_MODE=$DE25_HPS_PARTITION_MODE" )
if [[ -n ${DE25_HPS_PARTITION_QDB:-} ]]; then
    hps_partition_qdb=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_HPS_PARTITION_QDB")
    docker_args+=( -e "DE25_HPS_PARTITION_QDB=$hps_partition_qdb" )
fi
if [[ -n ${DE25_EXPECTED_HPS_IO_HASH_FILE:-} ]]; then
    expected_hash_file=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_EXPECTED_HPS_IO_HASH_FILE")
    docker_args+=( -e "DE25_EXPECTED_HPS_IO_HASH_FILE=$expected_hash_file" )
fi
if [[ -n ${DE25_AO486_OUTPUT_RBF:-} ]]; then
    ao486_output_rbf=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_AO486_OUTPUT_RBF")
    docker_args+=( -e "DE25_AO486_OUTPUT_RBF=$ao486_output_rbf" )
fi

exec docker "${docker_args[@]}" "$image" bash -lc \
    '/work/PC110-Mister/mister-de25/scripts/build-ao486.sh'
