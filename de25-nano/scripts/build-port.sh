#!/usr/bin/env bash
set -euo pipefail

target_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo_root=$(cd "$target_root/.." && pwd)
workspace_root=$repo_root
project=DE25_PC110_PORT
output_rbf=$target_root/artifacts/DE25_PC110_PORT.rbf
hps_bootloader=${DE25_HPS_BOOTLOADER:-$target_root/artifacts/u-boot-spl-dtb.hex}
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
quartus_home=${QUARTUS_HOME_DIR:-$HOME/quartus-pro-home}
host_uid=$(id -u)
host_gid=$(id -g)

generate_and_build() {
    source "$repo_root/mister-de25/scripts/acquire-ghrd-build-lock.sh"
    if [[ ! -s $hps_bootloader ]]; then
        echo "HPS bootloader not found: $hps_bootloader" >&2
        exit 1
    fi
    "$repo_root/mister-de25/scripts/prepare-ghrd-worktree.sh" "$project" >/dev/null
    cd "$target_root/ip"
    rm -rf pc110_pll ip/pc110_pll
    rm -f pc110_pll.qsys create_pc110_pll.qpf create_pc110_pll.qsf \
        create_pc110_hps.qpf create_pc110_hps.qsf \
        ../vendor/terasic-ghrd/pc110_hps.qsys
    qsys-generate --upgrade-ip-cores \
        ../vendor/terasic-ghrd/hps_subsys/ip/hps_subsys/agilex_hps.ip
    qsys-generate --upgrade-ip-cores \
        ../vendor/terasic-ghrd/peripheral_subsys/ip/peripheral_subsys/sysid.ip
    qsys-script \
        --quartus-project="$target_root/quartus/$project" \
        --rev="$project" \
        --script=create_pc110_pll.tcl
    qsys-script \
        --quartus-project="$target_root/quartus/$project" \
        --rev="$project" \
        --script=create_pc110_hps.tcl
    cd "$target_root/quartus"
    quartus_ipgenerate "$project" -c "$project" --run_default_mode_op
    quartus_syn "$project" -c "$project"
    quartus_fit "$project" -c "$project"
    quartus_asm "$project" -c "$project"
    quartus_sta "$project" -c "$project"
    "$repo_root/mister-de25/scripts/check-timing-summary.sh" \
        "output_files_port/$project.sta.summary"
    "$repo_root/mister-de25/scripts/make-hps-first-rbf.sh" \
        "output_files_port/$project.sof" "$output_rbf" "$hps_bootloader"
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
    -v "$target_root:/work/de25-nano"
    -v "$repo_root/mister-de25:/work/mister-de25"
    -v "$quartus_home:/quartus-home"
    -w /work/de25-nano
)

if [[ -n ${LM_LICENSE_FILE:-} ]]; then
    docker_args+=( -e "LM_LICENSE_FILE=$LM_LICENSE_FILE" )
fi
if [[ -n ${SALT_LICENSE_SERVER:-} ]]; then
    docker_args+=( -e "SALT_LICENSE_SERVER=$SALT_LICENSE_SERVER" )
fi

exec docker "${docker_args[@]}" "$image" bash -lc \
    '/work/de25-nano/scripts/build-port.sh'
