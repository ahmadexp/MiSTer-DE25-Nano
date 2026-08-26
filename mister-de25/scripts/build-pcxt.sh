#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$platform_root/.." && pwd)
project=${DE25_PCXT_PROJECT:-DE25_MISTER_PCXT}
output_directory=${DE25_PCXT_OUTPUT_DIRECTORY:-output_files_pcxt}
output_rbf=${DE25_PCXT_OUTPUT_RBF:-$platform_root/artifacts/pcxt/PCXT_20260815.rbf}
hps_bootloader=${DE25_HPS_BOOTLOADER:-$workspace_root/de25-nano/artifacts/u-boot-spl-dtb.hex}
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
quartus_home=${QUARTUS_HOME_DIR:-$HOME/quartus-pro-home}
host_uid=$(id -u)
host_gid=$(id -g)

if command -v git >/dev/null 2>&1; then
    "$platform_root/scripts/apply-pcxt-patches.sh"
fi

generate_and_build() {
    source "$platform_root/scripts/acquire-ghrd-build-lock.sh"
    if [[ ! -f $hps_bootloader ]]; then
        echo "HPS bootloader not found: $hps_bootloader" >&2
        exit 1
    fi
    printf '`define BUILD_DATE "260815"\n' > \
        "$platform_root/upstream/cores/PCXT/build_id.v"
    ghrd_root=$("$platform_root/scripts/prepare-ghrd-worktree.sh" "$project")
    cd "$platform_root/ip"
    rm -rf mister_pll pcxt_core_pll \
        ip/mister_pll ip/pcxt_core_pll \
        "$ghrd_root/mister_hps" "$ghrd_root/ip/mister_hps"
    rm -f mister_pll.qsys pcxt_core_pll.qsys \
        "$ghrd_root/mister_hps.qsys"
    qsys-generate --upgrade-ip-cores \
        "$ghrd_root/hps_subsys/ip/hps_subsys/agilex_hps.ip"
    qsys-generate --upgrade-ip-cores \
        "$ghrd_root/peripheral_subsys/ip/peripheral_subsys/sysid.ip"
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_mister_pll.tcl
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_pcxt_core_pll.tcl
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_mister_hps.tcl
    cd "$platform_root/quartus"
    quartus_sh --clean -c "$project" "$project"
    quartus_ipgenerate "$project" -c "$project" --run_default_mode_op \
        --parallel=off
    "$platform_root/scripts/quartus-syn-de25.sh" "$project"
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
[[ -z ${LM_LICENSE_FILE:-} ]] || docker_args+=( -e "LM_LICENSE_FILE=$LM_LICENSE_FILE" )
[[ -z ${SALT_LICENSE_SERVER:-} ]] || docker_args+=( -e "SALT_LICENSE_SERVER=$SALT_LICENSE_SERVER" )
[[ -z ${DE25_ROOT_SHELL_MODE:-} ]] || docker_args+=( -e "DE25_ROOT_SHELL_MODE=$DE25_ROOT_SHELL_MODE" )
if [[ -n ${DE25_ROOT_SHELL_QDB:-} ]]; then
    root_shell_qdb=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_ROOT_SHELL_QDB")
    docker_args+=( -e "DE25_ROOT_SHELL_QDB=$root_shell_qdb" )
fi
[[ -z ${DE25_HPS_PARTITION_MODE:-} ]] || docker_args+=( -e "DE25_HPS_PARTITION_MODE=$DE25_HPS_PARTITION_MODE" )
if [[ -n ${DE25_HPS_PARTITION_QDB:-} ]]; then
    hps_partition_qdb=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_HPS_PARTITION_QDB")
    docker_args+=( -e "DE25_HPS_PARTITION_QDB=$hps_partition_qdb" )
fi
[[ -z ${DE25_HPS_RESET_RECOVERY:-} ]] || docker_args+=( -e "DE25_HPS_RESET_RECOVERY=$DE25_HPS_RESET_RECOVERY" )
[[ -z ${DE25_HPS_RESET_V1_REPRO:-} ]] || docker_args+=( -e "DE25_HPS_RESET_V1_REPRO=$DE25_HPS_RESET_V1_REPRO" )
[[ -z ${DE25_HPS_RESET_V1_RECOVERY:-} ]] || docker_args+=( -e "DE25_HPS_RESET_V1_RECOVERY=$DE25_HPS_RESET_V1_RECOVERY" )
[[ -z ${DE25_PCXT_PROJECT:-} ]] || docker_args+=( -e "DE25_PCXT_PROJECT=$DE25_PCXT_PROJECT" )
[[ -z ${DE25_PCXT_OUTPUT_DIRECTORY:-} ]] || docker_args+=( -e "DE25_PCXT_OUTPUT_DIRECTORY=$DE25_PCXT_OUTPUT_DIRECTORY" )
if [[ -n ${DE25_EXPECTED_HPS_IO_HASH_FILE:-} ]]; then
    expected_hash_file=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_EXPECTED_HPS_IO_HASH_FILE")
    docker_args+=( -e "DE25_EXPECTED_HPS_IO_HASH_FILE=$expected_hash_file" )
fi
if [[ -n ${DE25_PCXT_OUTPUT_RBF:-} ]]; then
    pcxt_output_rbf=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_PCXT_OUTPUT_RBF")
    docker_args+=( -e "DE25_PCXT_OUTPUT_RBF=$pcxt_output_rbf" )
fi

exec docker "${docker_args[@]}" "$image" bash -lc \
    '/work/PC110-Mister/mister-de25/scripts/build-pcxt.sh'
