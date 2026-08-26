#!/usr/bin/env bash
set -euo pipefail

target_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
project=DE25_SI5332_PROBE
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
quartus_home=${QUARTUS_HOME_DIR:-$HOME/quartus-pro-home}
host_uid=$(id -u)
host_gid=$(id -g)

if command -v quartus_sh >/dev/null 2>&1; then
    cd "$target_root/quartus"
    exec quartus_sh --flow compile "$project"
fi

exec docker run --rm --network host \
    --user "$host_uid:$host_gid" \
    -e HOME=/quartus-home \
    -v "$target_root:/work" \
    -v "$quartus_home:/quartus-home" \
    -w /work/quartus \
    "$image" quartus_sh --flow compile "$project"
