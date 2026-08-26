#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$platform_root/.." && pwd)
project=DE25_NES_STANDALONE
rom=${NES_ROM:-$platform_root/artifacts/private/Super_Mario_Bros.nes}
rom_hex=$platform_root/artifacts/private/nes_autoload.hex
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
quartus_home=${QUARTUS_HOME_DIR:-$HOME/quartus-pro-home}
host_uid=$(id -u)
host_gid=$(id -g)

generate_rom_hex() {
    if [[ ! -f $rom ]]; then
        echo "NES ROM not found: $rom" >&2
        exit 1
    fi
    if [[ $(wc -c < "$rom") -ne 40976 ]]; then
        echo "This standalone mapper-0 test expects the 40,976-byte SMB image" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$rom_hex")"
    od -An -v -tx1 "$rom" | tr -s ' ' '\n' | sed '/^$/d' > "$rom_hex"
    if [[ $(wc -l < "$rom_hex") -ne 40976 ]]; then
        echo "ROM-to-hex conversion produced the wrong byte count" >&2
        exit 1
    fi
}

generate_and_build() {
    source "$platform_root/scripts/acquire-ghrd-build-lock.sh"
    generate_rom_hex
    printf '`define BUILD_DATE "260822"\n' > \
        "$platform_root/upstream/cores/NES/build_id.v"

    cd "$platform_root/ip"
    rm -rf mister_pll nes_core_pll_cal ip/mister_pll ip/nes_core_pll_cal
    rm -f mister_pll.qsys nes_core_pll_cal.qsys
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_mister_pll.tcl
    qsys-script --quartus-project="$platform_root/quartus/$project" \
        --rev="$project" --script=create_nes_core_pll_cal.tcl

    cd "$platform_root/quartus"
    quartus_sh --clean -c "$project" "$project"
    quartus_ipgenerate "$project" -c "$project" --run_default_mode_op \
        --parallel=off
    "$platform_root/scripts/fix-emif-calibration-ip.sh" nes_core_pll_cal
    "$platform_root/scripts/quartus-syn-de25.sh" "$project"
    quartus_fit "$project" -c "$project"
    quartus_asm "$project" -c "$project"
    quartus_sta "$project" -c "$project"
}

if command -v quartus_sh >/dev/null 2>&1; then
    generate_and_build
    exit
fi

generate_rom_hex
docker_args=(
    run --rm --network host --user "$host_uid:$host_gid"
    -e HOME=/quartus-home
    -e NES_ROM=/work/PC110-Mister/mister-de25/artifacts/private/Super_Mario_Bros.nes
    -v "$workspace_root:/work/PC110-Mister"
    -v "$quartus_home:/quartus-home"
    -w /work/PC110-Mister/mister-de25
)
[[ -z ${LM_LICENSE_FILE:-} ]] || docker_args+=( -e "LM_LICENSE_FILE=$LM_LICENSE_FILE" )
[[ -z ${SALT_LICENSE_SERVER:-} ]] || docker_args+=( -e "SALT_LICENSE_SERVER=$SALT_LICENSE_SERVER" )

exec docker "${docker_args[@]}" "$image" bash -lc \
    '/work/PC110-Mister/mister-de25/scripts/build-nes-standalone.sh'
