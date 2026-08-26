#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF' >&2
Usage: make-update-bundle.sh [--runtime-only] OUTPUT_DIRECTORY

Environment:
  MISTER_DE25_MAIN_BINARY        Main executable to package
  MISTER_DE25_MENU_RBF           Menu runtime RBF to package
  MISTER_DE25_BUILD_MATRIX       Core matrix to package
  MISTER_DE25_PLATFORM_HASH_FILE Matching QSPI HPS I/O hash metadata
EOF
}

runtime_only=0
if [[ ${1:-} == --runtime-only ]]; then
    runtime_only=1
    shift
fi
if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output=$1
main_binary=${MISTER_DE25_MAIN_BINARY:-$platform_root/artifacts/main/MiSTer}
menu_rbf=${MISTER_DE25_MENU_RBF:-$platform_root/artifacts/menu/menu.rbf}
build_matrix=${MISTER_DE25_BUILD_MATRIX:-$platform_root/build-matrix.tsv}
rbfs=("$menu_rbf")
core_categories=()
core_rbfs=()
while IFS=$'\t' read -r category artifact; do
    core_categories+=("$category")
    core_rbfs+=("$platform_root/$artifact")
    rbfs+=("$platform_root/$artifact")
done < <("$platform_root/scripts/list-packaged-artifacts.sh" --managed "$build_matrix")
platform_hash_file=${MISTER_DE25_PLATFORM_HASH_FILE:-$(dirname "$menu_rbf")/qspi.hps-io-hash}
runtime_catalog=$(mktemp "${TMPDIR:-/tmp}/mister-de25-cores.XXXXXXXX.tsv")
trap 'rm -f -- "$runtime_catalog"' EXIT
"$platform_root/scripts/make-runtime-core-catalog.sh" --managed \
    "$runtime_catalog" "$build_matrix"

if [[ -e $output ]]; then
    echo "Refusing to overwrite existing path: $output" >&2
    exit 1
fi

read_hps_hash() {
    local hash_file=$1 hash
    if [[ ! -s $hash_file ]]; then
        echo "HPS I/O compatibility metadata not found: $hash_file" >&2
        exit 1
    fi
    hash=$(tr -d '[:space:]' <"$hash_file" | tr '[:lower:]' '[:upper:]')
    if [[ ! $hash =~ ^[0-9A-F]{64}$ ]]; then
        echo "Invalid HPS I/O compatibility metadata: $hash_file" >&2
        exit 1
    fi
    printf '%s' "$hash"
}

if [[ $runtime_only -eq 0 ]]; then
    # Prove the release is a single HPS-first platform before creating any
    # output. This prevents a partially rebuilt catalog from becoming an
    # installable bundle. Runtime-only maintenance bundles contain no fabric
    # or FAT payload, so mixed build artifacts are irrelevant to them.
    platform_hash=$(read_hps_hash "$platform_hash_file")
    for rbf in "${rbfs[@]}"; do
        [[ -s $rbf ]] || { echo "Update input not found: $rbf" >&2; exit 1; }
        rbf_hash=$(read_hps_hash "$rbf.hps-io-hash")
        if [[ $rbf_hash != "$platform_hash" ]]; then
            echo "Refusing mixed HPS I/O hashes in the update bundle:" >&2
            echo "  QSPI platform: $platform_hash" >&2
            echo "  $(basename "$rbf"): $rbf_hash" >&2
            exit 1
        fi
        [[ -s $rbf.sha256 ]] || {
            echo "RBF SHA-256 metadata not found: $rbf.sha256" >&2
            exit 1
        }
        expected_digest=$(tr -d '[:space:]' <"$rbf.sha256" | \
            tr '[:upper:]' '[:lower:]')
        if [[ ! $expected_digest =~ ^[0-9a-f]{64}$ ]]; then
            echo "Invalid RBF SHA-256 metadata: $rbf.sha256" >&2
            exit 1
        fi
        if [[ $(sha256sum "$rbf" 2>/dev/null | awk '{print $1}' || \
            shasum -a 256 "$rbf" | awk '{print $1}') != "$expected_digest" ]]; then
            echo "RBF SHA-256 metadata does not match: $rbf" >&2
            exit 1
        fi
    done
fi

mkdir -p "$output/payload"
manifest=$output/manifest.tsv
printf '# sha256\tsize\tmode\tscope\tdestination\tpayload\n' >"$manifest"

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

file_size() {
    if stat -c %s "$1" >/dev/null 2>&1; then
        stat -c %s "$1"
    else
        stat -f %z "$1"
    fi
}

verify_digest_sidecar() {
    local artifact=$1 sidecar=$1.sha256 expected actual
    [[ -s $sidecar ]] || {
        echo "SHA-256 metadata not found: $sidecar" >&2
        exit 1
    }
    expected=$(tr -d '[:space:]' <"$sidecar" | tr '[:upper:]' '[:lower:]')
    if [[ ! $expected =~ ^[0-9a-f]{64}$ ]]; then
        echo "Invalid SHA-256 metadata: $sidecar" >&2
        exit 1
    fi
    actual=$(hash_file "$artifact")
    if [[ $actual != "$expected" ]]; then
        echo "SHA-256 metadata does not match: $artifact" >&2
        exit 1
    fi
}

add_payload() {
    local source=$1
    local scope=$2
    local destination=$3
    local mode=$4
    local payload=$5
    local payload_path=$output/payload/$payload

    if [[ ! -f $source ]]; then
        echo "Update input not found: $source" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$payload_path")"
    install -m "$mode" "$source" "$payload_path"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(hash_file "$payload_path")" "$(file_size "$payload_path")" \
        "$mode" "$scope" "$destination" "$payload" >>"$manifest"
}

if [[ $runtime_only -eq 0 ]]; then
    [[ -x $main_binary ]] || {
        echo "ARM64 Main release artifact is missing or not executable: $main_binary" >&2
        exit 1
    }
    verify_digest_sidecar "$main_binary"

    add_payload "$menu_rbf" \
        fat menu.rbf 0644 menu.rbf
    add_payload "$menu_rbf.hps-io-hash" \
        fat menu.rbf.hps-io-hash 0644 menu.rbf.hps-io-hash
    add_payload "$menu_rbf.sha256" \
        fat menu.rbf.sha256 0644 menu.rbf.sha256
    for index in "${!core_rbfs[@]}"; do
        rbf=${core_rbfs[$index]}
        category=${core_categories[$index]}
        filename=${rbf##*/}
        payload_category=${category#_}
        add_payload "$rbf" fat "$category/$filename" 0644 \
            "cores/$payload_category/$filename"
        add_payload "$rbf.hps-io-hash" fat "$category/$filename.hps-io-hash" \
            0644 "cores/$payload_category/$filename.hps-io-hash"
        add_payload "$rbf.sha256" fat "$category/$filename.sha256" \
            0644 "cores/$payload_category/$filename.sha256"
    done
    add_payload "$main_binary" fat MiSTer 0755 MiSTer
    add_payload "$platform_root/sw/update_de25.sh" \
        fat Scripts/update_de25.sh 0755 update_de25.sh
fi
add_payload "$platform_root/sw/mister-de25-load" \
    root usr/libexec/mister-de25-load 0755 mister-de25-load
add_payload "$platform_root/sw/mister-de25-watchdog-run" \
    root usr/libexec/mister-de25-watchdog-run 0755 mister-de25-watchdog-run
add_payload "$platform_root/sw/mister-de25-check-rbf" \
    root usr/libexec/mister-de25-check-rbf 0755 mister-de25-check-rbf
add_payload "$platform_root/sw/mister-de25-prune-cores" \
    root usr/libexec/mister-de25-prune-cores 0755 mister-de25-prune-cores
add_payload "$platform_root/sw/mister-de25-platform-migration" \
    root usr/libexec/mister-de25-platform-migration 0755 mister-de25-platform-migration
add_payload "$platform_root/sw/mister-de25-headless-migrate" \
    root usr/libexec/mister-de25-headless-migrate 0755 mister-de25-headless-migrate
add_payload "$platform_root/sw/mister-de25-test-rbf" \
    root usr/libexec/mister-de25-test-rbf 0755 mister-de25-test-rbf
add_payload "$platform_root/sw/mister-de25-select-core" \
    root usr/libexec/mister-de25-select-core 0755 mister-de25-select-core
add_payload "$platform_root/sw/mister-de25-process-core-request" \
    root usr/libexec/mister-de25-process-core-request 0755 mister-de25-process-core-request
add_payload "$platform_root/sw/mister-de25-core" \
    root usr/bin/mister-de25-core 0755 mister-de25-core
add_payload "$platform_root/sw/mister-de25-screenshot" \
    root usr/bin/mister-de25-screenshot 0755 mister-de25-screenshot
add_payload "$platform_root/sw/mister-de25-migrate" \
    root usr/bin/mister-de25-migrate 0755 mister-de25-migrate
add_payload "$platform_root/sw/mister-de25-bridge" \
    root usr/libexec/mister-de25-bridge 0755 mister-de25-bridge
add_payload "$runtime_catalog" \
    root etc/mister-de25/cores.tsv 0644 cores.tsv
add_payload "$platform_root/systemd/mister-de25-core-request.path" \
    root etc/systemd/system/mister-de25-core-request.path 0644 mister-de25-core-request.path
add_payload "$platform_root/systemd/mister-de25-core-request.service" \
    root etc/systemd/system/mister-de25-core-request.service 0644 mister-de25-core-request.service
add_payload "$platform_root/systemd/mister-de25-watchdog-keeper.service" \
    root etc/systemd/system/mister-de25-watchdog-keeper.service 0644 mister-de25-watchdog-keeper.service
add_payload "$platform_root/systemd/mister-de25-platform-migration.path" \
    root etc/systemd/system/mister-de25-platform-migration.path 0644 mister-de25-platform-migration.path
add_payload "$platform_root/systemd/mister-de25-platform-migration-request.service" \
    root etc/systemd/system/mister-de25-platform-migration-request.service 0644 mister-de25-platform-migration-request.service
add_payload "$platform_root/systemd/mister-de25-tmpfiles.conf" \
    root usr/lib/tmpfiles.d/mister-de25.conf 0644 mister-de25.conf
add_payload "$platform_root/systemd/mister-de25-preload.service" \
    root etc/systemd/system/mister-de25-preload.service 0644 mister-de25-preload.service
add_payload "$platform_root/systemd/mister.service" \
    root etc/systemd/system/mister.service 0644 mister.service

cp "$platform_root/README.md" "$output/README.md"
echo "DE25-Nano update bundle ready: $output"
echo "Manifest SHA-256: $(hash_file "$manifest")"
