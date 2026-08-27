#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$platform_root/.." && pwd)

: "${DE25_PERSONA_PROJECT:?missing DE25_PERSONA_PROJECT}"
: "${DE25_PERSONA_SOURCE_ID:?missing DE25_PERSONA_SOURCE_ID}"
: "${DE25_PERSONA_PATCH_DIR:?missing DE25_PERSONA_PATCH_DIR}"
: "${DE25_PERSONA_PLL_NAME:?missing DE25_PERSONA_PLL_NAME}"
: "${DE25_PERSONA_PLL_SCRIPT:?missing DE25_PERSONA_PLL_SCRIPT}"
: "${DE25_PERSONA_OUTPUT_DIRECTORY:?missing DE25_PERSONA_OUTPUT_DIRECTORY}"
: "${DE25_PERSONA_OUTPUT_RBF:?missing DE25_PERSONA_OUTPUT_RBF}"

project=$DE25_PERSONA_PROJECT
source_dir=$platform_root/upstream/official/$DE25_PERSONA_SOURCE_ID
patch_dir=$platform_root/patches/$DE25_PERSONA_PATCH_DIR
pll_name=$DE25_PERSONA_PLL_NAME
pll_script=$DE25_PERSONA_PLL_SCRIPT
extra_pll_name=${DE25_PERSONA_EXTRA_PLL_NAME:-}
extra_pll_script=${DE25_PERSONA_EXTRA_PLL_SCRIPT:-}
output_directory=$DE25_PERSONA_OUTPUT_DIRECTORY
output_rbf=$DE25_PERSONA_OUTPUT_RBF
hps_bootloader=${DE25_HPS_BOOTLOADER:-$workspace_root/de25-nano/artifacts/u-boot-spl-dtb.hex}
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
quartus_home_dir=${QUARTUS_HOME_DIR:-$HOME/quartus-pro-home}
host_uid=$(id -u)
host_gid=$(id -g)

if [[ -n $extra_pll_name || -n $extra_pll_script ]]; then
    [[ -n $extra_pll_name && -n $extra_pll_script ]] || {
        echo "Both DE25_PERSONA_EXTRA_PLL_NAME and DE25_PERSONA_EXTRA_PLL_SCRIPT are required" >&2
        exit 1
    }
fi

if [[ ${DE25_PERSONA_PATCHES_APPLIED:-0} != 1 ]]; then
    "$platform_root/scripts/apply-persona-patches.sh" "$source_dir" "$patch_dir"
fi

generate_and_build() {
    source "$platform_root/scripts/acquire-ghrd-build-lock.sh"
    [[ -f $hps_bootloader ]] || {
        echo "HPS bootloader not found: $hps_bootloader" >&2
        exit 1
    }

    printf '`define BUILD_DATE "%s"\n' "$(date +%y%m%d)" > \
        "$source_dir/build_id.v"

    ghrd_root=$("$platform_root/scripts/prepare-ghrd-worktree.sh" "$project")
    cd "$platform_root/ip"
    rm -rf mister_pll "$pll_name" ip/mister_pll "ip/$pll_name" \
        "$ghrd_root/mister_hps" "$ghrd_root/ip/mister_hps"
    rm -f mister_pll.qsys "$pll_name.qsys" "$ghrd_root/mister_hps.qsys"
    if [[ -n $extra_pll_name ]]; then
        rm -rf "$extra_pll_name" "ip/$extra_pll_name"
        rm -f "$extra_pll_name.qsys"
    fi

    qsys-generate --upgrade-ip-cores \
        "$ghrd_root/hps_subsys/ip/hps_subsys/agilex_hps.ip"
    qsys-generate --upgrade-ip-cores \
        "$ghrd_root/peripheral_subsys/ip/peripheral_subsys/sysid.ip"
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_mister_pll.tcl
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script="$pll_script"
    if [[ -n $extra_pll_name ]]; then
        qsys-script --quartus-project="$platform_root/quartus/$project" \
            --rev="$project" --script="$extra_pll_script"
    fi
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_mister_hps.tcl

    cd "$platform_root/quartus"
    quartus_sh --clean -c "$project" "$project"
    # The shared HPS system includes the LPDDR bridge. Quartus 25.3.1 can
    # intermittently lose a localhost worker while parallel IP generation is
    # packaging that EMIF dependency graph. Serial generation is slower but
    # deterministic, and is the proven path used by the PC110 persona.
    quartus_ipgenerate "$project" -c "$project" --parallel=off \
        --run_default_mode_op
    "$platform_root/scripts/quartus-syn-de25.sh" "$project"
    quartus_fit "$project" -c "$project"
    quartus_asm "$project" -c "$project"
    quartus_sta "$project" -c "$project"
    "$platform_root/scripts/check-timing-summary.sh" \
        "$output_directory/$project.sta.summary"
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
    -v "$workspace_root:/work/MiSTer-DE25-Nano"
    -v "$quartus_home_dir:/quartus-home"
    -w /work/MiSTer-DE25-Nano/mister-de25
)
if [[ -n ${DE25_DOCKER_NAME:-} ]]; then
    docker_args+=( --name "$DE25_DOCKER_NAME" )
fi
if [[ -n ${DE25_DOCKER_CPUS:-} ]]; then
    docker_args+=( --cpus "$DE25_DOCKER_CPUS" )
fi
if [[ -n ${DE25_DOCKER_CPUSET_CPUS:-} ]]; then
    docker_args+=( --cpuset-cpus "$DE25_DOCKER_CPUSET_CPUS" )
fi
if [[ -n ${DE25_DOCKER_CPUSET_MEMS:-} ]]; then
    docker_args+=( --cpuset-mems "$DE25_DOCKER_CPUSET_MEMS" )
fi
if [[ -n ${DE25_DOCKER_MEMORY:-} ]]; then
    docker_args+=( --memory "$DE25_DOCKER_MEMORY" )
fi
for variable in LM_LICENSE_FILE SALT_LICENSE_SERVER DE25_HPS_PARTITION_MODE; do
    [[ -z ${!variable:-} ]] || docker_args+=( -e "$variable=${!variable}" )
done
if [[ -n ${DE25_HPS_PARTITION_QDB:-} ]]; then
    docker_hps_qdb=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_HPS_PARTITION_QDB")
    docker_args+=( -e "DE25_HPS_PARTITION_QDB=$docker_hps_qdb" )
fi
if [[ -n ${DE25_EXPECTED_HPS_IO_HASH_FILE:-} ]]; then
    docker_hash_file=$("$platform_root/scripts/docker-workspace-path.sh" \
        "$workspace_root" "$DE25_EXPECTED_HPS_IO_HASH_FILE")
    docker_args+=( -e "DE25_EXPECTED_HPS_IO_HASH_FILE=$docker_hash_file" )
fi
docker_output_rbf=$("$platform_root/scripts/docker-workspace-path.sh" \
    "$workspace_root" "$output_rbf")
docker_args+=(
    -e "DE25_PERSONA_PROJECT=$project"
    -e "DE25_PERSONA_SOURCE_ID=$DE25_PERSONA_SOURCE_ID"
    -e "DE25_PERSONA_PATCH_DIR=$DE25_PERSONA_PATCH_DIR"
    -e "DE25_PERSONA_PLL_NAME=$pll_name"
    -e "DE25_PERSONA_PLL_SCRIPT=$pll_script"
    -e "DE25_PERSONA_OUTPUT_DIRECTORY=$output_directory"
    -e "DE25_PERSONA_OUTPUT_RBF=$docker_output_rbf"
    -e DE25_PERSONA_PATCHES_APPLIED=1
)
if [[ -n $extra_pll_name ]]; then
    docker_args+=(
        -e "DE25_PERSONA_EXTRA_PLL_NAME=$extra_pll_name"
        -e "DE25_PERSONA_EXTRA_PLL_SCRIPT=$extra_pll_script"
    )
fi

exec docker "${docker_args[@]}" "$image" bash -lc \
    '/work/MiSTer-DE25-Nano/mister-de25/scripts/build-simple-persona.sh'
