#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$platform_root/.." && pwd)
project=DE25_MISTER_INPUTTEST
output_rbf=${DE25_INPUTTEST_OUTPUT_RBF:-$platform_root/artifacts/inputtest/InputTest_20260812.rbf}
hps_bootloader=${DE25_HPS_BOOTLOADER:-$workspace_root/de25-nano/artifacts/u-boot-spl-dtb.hex}
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
quartus_home=${QUARTUS_HOME_DIR:-$HOME/quartus-pro-home}
host_uid=$(id -u)
host_gid=$(id -g)

if command -v git >/dev/null 2>&1; then
    "$platform_root/scripts/apply-inputtest-patches.sh"
fi

generate_and_build() {
    source "$platform_root/scripts/acquire-ghrd-build-lock.sh"
    if [[ ! -f $hps_bootloader ]]; then
        echo "HPS bootloader not found: $hps_bootloader" >&2
        exit 1
    fi
    # InputTest's legacy files are readmemh token streams, while an explicit
    # Agilex altsyncram requires Quartus MIF syntax. Stage deterministic MIFs
    # in the project directory where the RAM primitive resolves INIT_FILE.
    "$platform_root/scripts/readmemh-to-mif.sh" \
        "$platform_root/upstream/cores/InputTest/rtl/rom.hex" 32768 \
        "$platform_root/quartus/rom.mif"
    "$platform_root/scripts/readmemh-to-mif.sh" \
        "$platform_root/upstream/cores/InputTest/rtl/font.hex" 2048 \
        "$platform_root/quartus/font.mif"
    "$platform_root/scripts/readmemh-to-mif.sh" \
        "$platform_root/upstream/cores/InputTest/rtl/sprite.hex" 16384 \
        "$platform_root/quartus/sprite.mif"
    "$platform_root/scripts/readmemh-to-mif.sh" \
        "$platform_root/upstream/cores/InputTest/rtl/music.hex" 65536 \
        "$platform_root/quartus/music.mif"
    "$platform_root/scripts/readmemh-to-mif.sh" \
        "$platform_root/upstream/cores/InputTest/rtl/sound.hex" 16384 \
        "$platform_root/quartus/sound.mif"
    ghrd_root=$("$platform_root/scripts/prepare-ghrd-worktree.sh" "$project")
    cd "$platform_root/ip"
    rm -rf mister_pll inputtest_core_pll ip/mister_pll ip/inputtest_core_pll \
        "$ghrd_root/mister_hps" "$ghrd_root/ip/mister_hps"
    rm -f mister_pll.qsys inputtest_core_pll.qsys \
        "$ghrd_root/mister_hps.qsys"
    qsys-generate --upgrade-ip-cores \
        "$ghrd_root/hps_subsys/ip/hps_subsys/agilex_hps.ip"
    qsys-generate --upgrade-ip-cores \
        "$ghrd_root/peripheral_subsys/ip/peripheral_subsys/sysid.ip"
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_mister_pll.tcl
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_inputtest_core_pll.tcl
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_mister_hps.tcl
    cd "$platform_root/quartus"
    quartus_sh --clean -c "$project" "$project"
    quartus_ipgenerate "$project" -c "$project" --run_default_mode_op
    "$platform_root/scripts/quartus-syn-de25.sh" "$project"
    quartus_fit "$project" -c "$project"
    quartus_asm "$project" -c "$project"
    quartus_sta "$project" -c "$project"
    ../scripts/check-timing-summary.sh \
        "output_files_inputtest/$project.sta.summary"
    "$platform_root/scripts/make-hps-first-rbf.sh" \
        "output_files_inputtest/$project.sof" "$output_rbf" "$hps_bootloader"
}

if command -v quartus_sh >/dev/null 2>&1; then
    generate_and_build
    exit
fi

docker_args=(
    run --rm
    --network host
    --user "$host_uid:$host_gid"
    -e HOME=/quartus-home
    -v "$workspace_root:/work/PC110-Mister"
    -v "$quartus_home:/quartus-home"
    -w /work/PC110-Mister/mister-de25
)

if [[ -n ${LM_LICENSE_FILE:-} ]]; then
    docker_args+=( -e "LM_LICENSE_FILE=$LM_LICENSE_FILE" )
fi
if [[ -n ${SALT_LICENSE_SERVER:-} ]]; then
    docker_args+=( -e "SALT_LICENSE_SERVER=$SALT_LICENSE_SERVER" )
fi
if [[ -n ${DE25_ROOT_SHELL_MODE:-} ]]; then
    docker_args+=( -e "DE25_ROOT_SHELL_MODE=$DE25_ROOT_SHELL_MODE" )
fi
if [[ -n ${DE25_ROOT_SHELL_QDB:-} ]]; then
    root_shell_qdb=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_ROOT_SHELL_QDB")
    docker_args+=( -e "DE25_ROOT_SHELL_QDB=$root_shell_qdb" )
fi
if [[ -n ${DE25_HPS_PARTITION_MODE:-} ]]; then
    docker_args+=( -e "DE25_HPS_PARTITION_MODE=$DE25_HPS_PARTITION_MODE" )
fi
if [[ -n ${DE25_HPS_PARTITION_QDB:-} ]]; then
    hps_partition_qdb=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_HPS_PARTITION_QDB")
    docker_args+=( -e "DE25_HPS_PARTITION_QDB=$hps_partition_qdb" )
fi
if [[ -n ${DE25_HPS_RESET_RECOVERY:-} ]]; then
    docker_args+=( -e "DE25_HPS_RESET_RECOVERY=$DE25_HPS_RESET_RECOVERY" )
fi
if [[ -n ${DE25_HPS_RESET_V1_REPRO:-} ]]; then
    docker_args+=( -e "DE25_HPS_RESET_V1_REPRO=$DE25_HPS_RESET_V1_REPRO" )
fi
if [[ -n ${DE25_HPS_RESET_V1_RECOVERY:-} ]]; then
    docker_args+=( -e "DE25_HPS_RESET_V1_RECOVERY=$DE25_HPS_RESET_V1_RECOVERY" )
fi
if [[ -n ${DE25_EXPECTED_HPS_IO_HASH_FILE:-} ]]; then
    expected_hash_file=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_EXPECTED_HPS_IO_HASH_FILE")
    docker_args+=( -e "DE25_EXPECTED_HPS_IO_HASH_FILE=$expected_hash_file" )
fi
if [[ -n ${DE25_INPUTTEST_OUTPUT_RBF:-} ]]; then
    inputtest_output_rbf=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_INPUTTEST_OUTPUT_RBF")
    docker_args+=( -e "DE25_INPUTTEST_OUTPUT_RBF=$inputtest_output_rbf" )
fi

exec docker "${docker_args[@]}" "$image" bash -lc \
    '/work/PC110-Mister/mister-de25/scripts/build-inputtest.sh'
