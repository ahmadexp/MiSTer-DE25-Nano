#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$platform_root/.." && pwd)
project=${DE25_MENU_PROJECT:-DE25_MISTER_MENU}
output_directory=${DE25_MENU_OUTPUT_DIRECTORY:-output_files_menu}
output_rbf=${DE25_MENU_OUTPUT_RBF:-$platform_root/artifacts/menu/menu.rbf}
artifact_prefix=${DE25_MENU_ARTIFACT_PREFIX:-$platform_root/artifacts/menu/DE25_MISTER_MENU_HPS_FIRST}
qspi_jic=$artifact_prefix.hps.jic
# Legacy default retained: "$platform_root/artifacts/menu/DE25_MISTER_MENU_HPS_FIRST"
hps_bootloader=${DE25_HPS_BOOTLOADER:-$workspace_root/de25-nano/artifacts/u-boot-spl-dtb.hex}
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
quartus_home=${QUARTUS_HOME_DIR:-$HOME/quartus-pro-home}
host_uid=$(id -u)
host_gid=$(id -g)

if command -v git >/dev/null 2>&1; then
    "$platform_root/scripts/apply-menu-patches.sh"
fi

generate_and_build() {
    source "$platform_root/scripts/acquire-ghrd-build-lock.sh"
    if [[ ! -f $hps_bootloader ]]; then
        echo "HPS bootloader not found: $hps_bootloader" >&2
        exit 1
    fi
    if [[ ${DE25_INCREMENTAL_RECOMPILE:-0} != 1 ]]; then
        cd "$platform_root/ip"
        rm -rf mister_pll menu_core_pll ip/mister_pll ip/menu_core_pll
        rm -f mister_pll.qsys menu_core_pll.qsys

        # A reuse build imports the proven FDCD synthesized HPS partition.
        # Keep its matching generated HPS tree byte-for-byte and rebuild only
        # the fabric PLLs. Quartus 25.3.1 otherwise upgrades the Quartus 25.1
        # HPS component schema before QDB import and rejects its declared ports.
        if [[ ${DE25_HPS_PARTITION_MODE:-} != reuse ]]; then
            ghrd_root=$("$platform_root/scripts/prepare-ghrd-worktree.sh" "$project")
            rm -rf "$ghrd_root/mister_hps" "$ghrd_root/ip/mister_hps"
            rm -f "$ghrd_root/mister_hps.qsys"
            qsys-generate --upgrade-ip-cores \
                "$ghrd_root/hps_subsys/ip/hps_subsys/agilex_hps.ip"
            qsys-generate --upgrade-ip-cores \
                "$ghrd_root/peripheral_subsys/ip/peripheral_subsys/sysid.ip"
        fi
        qsys-script --quartus-project="$platform_root/quartus/$project" \
            --rev="$project" --script=create_mister_pll.tcl
        qsys-script --quartus-project="$platform_root/quartus/$project" \
            --rev="$project" --script=create_menu_core_pll.tcl
        if [[ ${DE25_HPS_PARTITION_MODE:-} != reuse ]]; then
            hps_qsys_args=(
                --quartus-project="$platform_root/quartus/$project"
                --rev="$project"
                --script=create_mister_hps.tcl
            )
            if [[ ${DE25_HPS_COMPAT_078:-0} == 1 ]]; then
                hps_qsys_args+=(--cmd="set legacy_no_vbuf 1")
            fi
            qsys-script "${hps_qsys_args[@]}"
        fi
        cd "$platform_root/quartus"
        # Generate the project IP exactly once before compilation. The
        # monolithic quartus_sh flow can upgrade the HPS IP a second time and
        # thereby change the HPS I/O hash between otherwise identical builds.
        # Also discard previous compiler snapshots unless this is an explicit
        # placement-preserving recovery recompile.
        if [[ ${DE25_SKIP_QUARTUS_CLEAN:-0} != 1 ]]; then
            quartus_sh --clean -c "$project" "$project"
        fi
        ipgenerate_args=("$project" -c "$project" --run_default_mode_op)
        if [[ ${DE25_IPGEN_PARALLEL:-on} == off ]]; then
            ipgenerate_args+=(--parallel=off)
        fi
        quartus_ipgenerate "${ipgenerate_args[@]}"
    else
        cd "$platform_root/quartus"
        if [[ ! -s $output_directory/$project.sof ]]; then
            echo "Incremental recovery requires a completed Menu baseline" >&2
            exit 1
        fi
    fi
    quartus_syn_args=("$project" -c "$project")
    if [[ ${DE25_HPS_COMPAT_078:-0} == 1 ]]; then
        quartus_syn_args+=(--set=VERILOG_MACRO=DE25_HPS_LEGACY_NO_VBUF)
    fi
    if [[ ${DE25_HPS_RESET_V1_RECOVERY:-0} == 1 ]]; then
        quartus_syn_args+=(--set=VERILOG_MACRO=DE25_HPS_RESET_V1_RECOVERY)
    elif [[ ${DE25_HPS_RESET_RECOVERY:-0} == 1 ]]; then
        quartus_syn_args+=(--set=VERILOG_MACRO=DE25_HPS_RESET_RECOVERY)
    elif [[ ${DE25_HPS_RESET_V1_REPRO:-0} == 1 ]]; then
        quartus_syn_args+=(--set=VERILOG_MACRO=DE25_HPS_RESET_V1_REPRO)
    fi
    quartus_syn "${quartus_syn_args[@]}"
    quartus_fit "$project" -c "$project"
    quartus_asm "$project" -c "$project"
    quartus_sta "$project" -c "$project"
    ../scripts/check-timing-summary.sh \
        "$output_directory/$project.sta.summary"
    quartus_sta -t ../scripts/report-sdram-timing.tcl "$project"
    mkdir -p "$(dirname "$output_rbf")"
    "$platform_root/scripts/make-hps-first-rbf.sh" \
        "$output_directory/$project.sof" "$output_rbf" "$hps_bootloader" \
        "$artifact_prefix"
    rm -f "$qspi_jic" "$artifact_prefix.jic"
    quartus_pfg -c "$output_directory/$project.sof" \
        "$artifact_prefix.jic" \
        -o "hps_path=$hps_bootloader" -o hps=1 \
        -o device=MT25QU128 -o flash_loader=A5EB013BB23B -o mode=ASX4
    test -s "$qspi_jic"
    qspi_hash=$("$platform_root/scripts/extract-hps-io-hash.sh" "$qspi_jic")
    runtime_hash=$(tr -d '[:space:]' <"$output_rbf.hps-io-hash")
    if [[ $qspi_hash != "$runtime_hash" ]]; then
        echo "Generated Menu JIC and RBF have different HPS I/O hashes" >&2
        exit 1
    fi
    printf '%s\n' "$qspi_hash" > \
        "$(dirname "$output_rbf")/qspi.hps-io-hash"
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

for menu_variable in \
    DE25_MENU_PROJECT DE25_MENU_OUTPUT_DIRECTORY DE25_MENU_OUTPUT_RBF \
    DE25_MENU_ARTIFACT_PREFIX; do
    if [[ -n ${!menu_variable:-} ]]; then
        menu_value=${!menu_variable}
        if [[ $menu_variable == DE25_MENU_OUTPUT_RBF ||
              $menu_variable == DE25_MENU_ARTIFACT_PREFIX ]]; then
            menu_value=$("$platform_root/scripts/docker-workspace-path.sh" \
                "$workspace_root" "$menu_value")
        fi
        docker_args+=( -e "$menu_variable=$menu_value" )
    fi
done

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
if [[ -n ${DE25_HPS_PARTITION_EXPORT_SNAPSHOT:-} ]]; then
    docker_args+=(
        -e "DE25_HPS_PARTITION_EXPORT_SNAPSHOT=$DE25_HPS_PARTITION_EXPORT_SNAPSHOT"
    )
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
if [[ -n ${DE25_SKIP_QUARTUS_CLEAN:-} ]]; then
    docker_args+=( -e "DE25_SKIP_QUARTUS_CLEAN=$DE25_SKIP_QUARTUS_CLEAN" )
fi
if [[ -n ${DE25_INCREMENTAL_RECOMPILE:-} ]]; then
    docker_args+=( -e "DE25_INCREMENTAL_RECOMPILE=$DE25_INCREMENTAL_RECOMPILE" )
fi
if [[ -n ${DE25_IPGEN_PARALLEL:-} ]]; then
    docker_args+=( -e "DE25_IPGEN_PARALLEL=$DE25_IPGEN_PARALLEL" )
fi
if [[ -n ${DE25_HPS_COMPAT_078:-} ]]; then
    docker_args+=( -e "DE25_HPS_COMPAT_078=$DE25_HPS_COMPAT_078" )
fi
if [[ -n ${DE25_EXPECTED_HPS_IO_HASH_FILE:-} ]]; then
    expected_hash_file=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_EXPECTED_HPS_IO_HASH_FILE")
    docker_args+=( -e "DE25_EXPECTED_HPS_IO_HASH_FILE=$expected_hash_file" )
fi

exec docker "${docker_args[@]}" "$image" bash -lc \
    '/work/PC110-Mister/mister-de25/scripts/build-menu.sh'
