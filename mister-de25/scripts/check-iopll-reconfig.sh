#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$platform_root/.." && pwd)
image=${QUARTUS_IMAGE:-alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}
quartus_home=${QUARTUS_HOME_DIR:-$HOME/quartus-pro-home}
host_uid=$(id -u)
host_gid=$(id -g)

run_probe() {
    "$platform_root/scripts/check-quartus-version.sh" 24 2
    # The probe declares its exact device and family itself. Do not attach it
    # to a build project: qsys-script persists generated QSYS/IP assignments
    # into the supplied QSF, and this deliberately unconnected diagnostic IP
    # must never become part of a core compilation.
    probe_dir=$(mktemp -d)
    trap 'rm -rf "$probe_dir"' RETURN
    cp "$platform_root/ip/inspect_agilex5_iopll_reconfig.tcl" \
        "$probe_dir/inspect_agilex5_iopll_reconfig.tcl"
    cp "$platform_root/ip/inspect_agilex5_die_revision.tcl" \
        "$probe_dir/inspect_agilex5_die_revision.tcl"
    output=$(cd "$probe_dir" && qsys-script \
        --script=inspect_agilex5_iopll_reconfig.tcl 2>&1)
    printf '%s\n' "$output"

    expected='IOPLL interfaces: refclk locked reset core_avl_address core_avl_clk core_avl_read core_avl_readdata core_avl_write core_avl_writedata outclk0'
    if [[ $output != *"$expected"* ]]; then
        echo "Agilex 5 HVIO IOPLL reconfiguration ports were not exposed" >&2
        exit 1
    fi

    die_output=$(cd "$probe_dir" && qsys-script \
        --script=inspect_agilex5_die_revision.tcl 2>&1)
    printf '%s\n' "$die_output"

    if [[ $die_output != *"DE25 die types: MAIN_SM4"* ||
          $die_output != *"DE25 die revisions: MAIN_SM4_REVB"* ]]; then
        echo "DE25 OPN did not resolve to the validated MAIN_SM4_REVB die" >&2
        exit 1
    fi

    echo "PASS: DE25 device is not the HVIO-IOPLL-ineligible SM7 rev-A die"
    echo "PASS: Agilex 5 HVIO IOPLL reconfiguration interface is available"
}

if command -v quartus_sh >/dev/null 2>&1; then
    run_probe
    exit
fi

docker_args=(
    run --rm
    --network host
    --user "$host_uid:$host_gid"
    -e HOME=/quartus-home
    -v "$workspace_root:/work/MiSTer-DE25-Nano"
    -v "$quartus_home:/quartus-home"
    -w /work/MiSTer-DE25-Nano/mister-de25
)

if [[ -n ${LM_LICENSE_FILE:-} ]]; then
    docker_args+=( -e "LM_LICENSE_FILE=$LM_LICENSE_FILE" )
fi
if [[ -n ${SALT_LICENSE_SERVER:-} ]]; then
    docker_args+=( -e "SALT_LICENSE_SERVER=$SALT_LICENSE_SERVER" )
fi

exec docker "${docker_args[@]}" "$image" bash -lc \
    '/work/MiSTer-DE25-Nano/mister-de25/scripts/check-iopll-reconfig.sh'
