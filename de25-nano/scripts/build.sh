#!/usr/bin/env bash
set -euo pipefail

target_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
project=DE25_PC110_DIAG
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
quartus_home=${QUARTUS_HOME_DIR:-$HOME/quartus-pro-home}
host_uid=$(id -u)
host_gid=$(id -g)

if command -v quartus_sh >/dev/null 2>&1; then
    cd "$target_root/quartus"
    exec quartus_sh --flow compile "$project"
fi

docker_args=(
    run --rm
    --network host
    --user "$host_uid:$host_gid"
    -e HOME=/quartus-home
    -v "$target_root:/work"
    -v "$quartus_home:/quartus-home"
    -w /work/quartus
)

if [[ -n ${LM_LICENSE_FILE:-} ]]; then
    docker_args+=( -e "LM_LICENSE_FILE=$LM_LICENSE_FILE" )
fi
if [[ -n ${SALT_LICENSE_SERVER:-} ]]; then
    docker_args+=( -e "SALT_LICENSE_SERVER=$SALT_LICENSE_SERVER" )
fi

exec docker "${docker_args[@]}" "$image" quartus_sh --flow compile "$project"
