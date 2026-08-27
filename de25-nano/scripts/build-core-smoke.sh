#!/usr/bin/env bash
set -euo pipefail

target_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo_root=$(cd "$target_root/.." && pwd)
project=DE25_PC110_CORE_SMOKE
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
quartus_home=${QUARTUS_HOME_DIR:-$HOME/quartus-pro-home}
host_uid=$(id -u)
host_gid=$(id -g)

generate_and_build() {
    cd "$target_root/ip"
    rm -f pc110_pll.qsys create_pc110_pll.qpf create_pc110_pll.qsf
    qsys-script \
        --quartus-project="$target_root/quartus/$project" \
        --rev="$project" \
        --script=create_pc110_pll.tcl
    cd "$target_root/quartus"
    quartus_sh --flow compile "$project"
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

exec docker "${docker_args[@]}" "$image" bash -lc '
    cd /work/de25-nano/ip
    rm -f pc110_pll.qsys create_pc110_pll.qpf create_pc110_pll.qsf
    qsys-script \
        --quartus-project=/work/de25-nano/quartus/DE25_PC110_CORE_SMOKE \
        --rev=DE25_PC110_CORE_SMOKE \
        --script=create_pc110_pll.tcl
    cd /work/de25-nano/quartus
    quartus_sh --flow compile DE25_PC110_CORE_SMOKE
'
