#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: extract-hps-io-hash.sh FPGA_CONFIGURATION_FILE" >&2
    exit 2
fi

input=$1
if [[ ! -s $input ]]; then
    echo "FPGA configuration file is missing or empty: $input" >&2
    exit 1
fi

inspect_rbf() {
    if [[ -n ${QUARTUS_PFG:-} ]]; then
        "$QUARTUS_PFG" -i "$input"
        return
    fi
    if command -v quartus_pfg >/dev/null 2>&1; then
        quartus_pfg -i "$input"
        return
    fi
    if ! command -v docker >/dev/null 2>&1; then
        echo "quartus_pfg and Docker are unavailable" >&2
        return 1
    fi

    local script_dir platform_root workspace_root absolute_input container_input
    local image host_uid host_gid
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    platform_root=$(cd "$script_dir/.." && pwd)
    workspace_root=$(cd "$platform_root/.." && pwd)
    absolute_input=$(cd "$(dirname "$input")" && printf '%s/%s\n' \
        "$PWD" "$(basename "$input")")
    case $absolute_input in
        "$workspace_root"/*) ;;
        *)
            echo "RBF inspection input must be inside the workspace: $input" >&2
            return 1
            ;;
    esac
    container_input=/work/MiSTer-DE25-Nano/${absolute_input#"$workspace_root/"}
    image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
    host_uid=$(id -u)
    host_gid=$(id -g)
    docker run --rm --user "$host_uid:$host_gid" \
        -v "$workspace_root:/work/MiSTer-DE25-Nano:ro" \
        -w /work/MiSTer-DE25-Nano "$image" quartus_pfg -i "$container_input"
}

inspection=$(inspect_rbf 2>&1) || {
    printf '%s\n' "$inspection" >&2
    exit 1
}
hashes=$(printf '%s\n' "$inspection" |
    awk '/HPS IO hash: [0-9A-Fa-f]+$/ {print toupper($NF)}' | sort -u)
if [[ $(printf '%s\n' "$hashes" | grep -Ec '^[0-9A-F]{64}$') -ne 1 ]]; then
    echo "Unable to extract exactly one HPS I/O hash from $input" >&2
    exit 1
fi

printf '%s\n' "$hashes"
