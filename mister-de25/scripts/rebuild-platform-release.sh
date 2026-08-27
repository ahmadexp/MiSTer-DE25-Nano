#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$platform_root/.." && pwd)
hps_qdb=
hps_hash_file=
build_main=1
bundle_dir=
image_base=
image_output=

usage() {
    cat <<'EOF' >&2
Usage: rebuild-platform-release.sh --hps-qdb FILE --hps-hash FILE
       [--skip-main] [--bundle DIRECTORY] [--image BASE.img OUTPUT.img]

Rebuilds Menu and every registered DE25 core against one reusable HPS partition,
optionally rebuilds ARM64 Main, verifies every artifact, then optionally creates
the update bundle and installable SD image.
EOF
    exit 2
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --hps-qdb)
            [[ $# -ge 2 ]] || usage
            hps_qdb=$2
            shift 2
            ;;
        --hps-hash)
            [[ $# -ge 2 ]] || usage
            hps_hash_file=$2
            shift 2
            ;;
        --skip-main)
            build_main=0
            shift
            ;;
        --bundle)
            [[ $# -ge 2 ]] || usage
            bundle_dir=$2
            shift 2
            ;;
        --image)
            [[ $# -ge 3 ]] || usage
            image_base=$2
            image_output=$3
            shift 3
            ;;
        --help|-h)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

[[ -n $hps_qdb && -n $hps_hash_file ]] || usage
[[ -s $hps_qdb ]] || { echo "HPS partition QDB not found: $hps_qdb" >&2; exit 1; }
[[ -s $hps_hash_file ]] || {
    echo "HPS I/O hash file not found: $hps_hash_file" >&2
    exit 1
}
hps_qdb=$(cd "$(dirname "$hps_qdb")" && printf '%s/%s\n' "$PWD" "$(basename "$hps_qdb")")
hps_hash_file=$(cd "$(dirname "$hps_hash_file")" && printf '%s/%s\n' "$PWD" "$(basename "$hps_hash_file")")
case $hps_qdb in
    "$workspace_root"/*) ;;
    *) echo "HPS partition QDB must be inside the workspace" >&2; exit 1 ;;
esac
case $hps_hash_file in
    "$workspace_root"/*) ;;
    *) echo "HPS I/O hash file must be inside the workspace" >&2; exit 1 ;;
esac

expected_hash=$(tr -d '[:space:]' <"$hps_hash_file" | tr '[:lower:]' '[:upper:]')
if [[ ! $expected_hash =~ ^[0-9A-F]{64}$ ]]; then
    echo "Invalid HPS I/O hash: $hps_hash_file" >&2
    exit 1
fi

partition_qdb_env=$hps_qdb
if ! command -v quartus_sh >/dev/null 2>&1; then
    partition_qdb_env=/work/PC110-Mister/${hps_qdb#"$workspace_root/"}
fi
export DE25_HPS_PARTITION_MODE=reuse
export DE25_HPS_PARTITION_QDB=$partition_qdb_env
export DE25_EXPECTED_HPS_IO_HASH_FILE=$hps_hash_file

if [[ $build_main == 1 ]]; then
    "$platform_root/scripts/build-main-aarch64.sh"
fi
"$platform_root/scripts/build-menu.sh"
"$platform_root/scripts/build-catalog.sh" --registered

verify_artifact() {
    local artifact=$1 artifact_hash embedded_hash digest actual_digest
    [[ -s $artifact ]] || { echo "Release artifact is missing: $artifact" >&2; exit 1; }
    [[ -s $artifact.hps-io-hash ]] || {
        echo "Release HPS metadata is missing: $artifact.hps-io-hash" >&2
        exit 1
    }
    artifact_hash=$(tr -d '[:space:]' <"$artifact.hps-io-hash" | \
        tr '[:lower:]' '[:upper:]')
    if [[ $artifact_hash != "$expected_hash" ]]; then
        echo "Release artifact has the wrong HPS I/O hash: $artifact" >&2
        exit 1
    fi
    embedded_hash=$("$platform_root/scripts/extract-hps-io-hash.sh" "$artifact")
    if [[ $embedded_hash != "$artifact_hash" ]]; then
        echo "Release HPS metadata does not match the RBF payload: $artifact" >&2
        echo "  Embedded HPS I/O hash: $embedded_hash" >&2
        echo "  Metadata HPS I/O hash: $artifact_hash" >&2
        exit 1
    fi
    [[ -s $artifact.sha256 ]] || {
        echo "Release digest is missing: $artifact.sha256" >&2
        exit 1
    }
    digest=$(tr -d '[:space:]' <"$artifact.sha256" | tr '[:upper:]' '[:lower:]')
    if command -v sha256sum >/dev/null 2>&1; then
        actual_digest=$(sha256sum "$artifact" | awk '{print $1}')
    else
        actual_digest=$(shasum -a 256 "$artifact" | awk '{print $1}')
    fi
    if [[ $digest != "$actual_digest" ]]; then
        echo "Release digest does not match: $artifact" >&2
        exit 1
    fi
}

verify_release_digest() {
    local artifact=$1 digest actual_digest
    [[ -s $artifact && -s $artifact.sha256 ]] || {
        echo "Release artifact or digest is missing: $artifact" >&2
        exit 1
    }
    digest=$(tr -d '[:space:]' <"$artifact.sha256" | tr '[:upper:]' '[:lower:]')
    [[ $digest =~ ^[0-9a-f]{64}$ ]] || {
        echo "Release digest is invalid: $artifact.sha256" >&2
        exit 1
    }
    if command -v sha256sum >/dev/null 2>&1; then
        actual_digest=$(sha256sum "$artifact" | awk '{print $1}')
    else
        actual_digest=$(shasum -a 256 "$artifact" | awk '{print $1}')
    fi
    [[ $digest == "$actual_digest" ]] || {
        echo "Release digest does not match: $artifact" >&2
        exit 1
    }
}

verify_artifact "$platform_root/artifacts/menu/menu.rbf"
while IFS=$'\t' read -r _category artifact; do
    verify_artifact "$platform_root/$artifact"
done < <("$platform_root/scripts/list-packaged-artifacts.sh" --managed)

qspi_hash=$(tr -d '[:space:]' <"$platform_root/artifacts/menu/qspi.hps-io-hash" | \
    tr '[:lower:]' '[:upper:]')
[[ $qspi_hash == "$expected_hash" ]] || {
    echo "Menu QSPI JIC has the wrong HPS I/O hash" >&2
    exit 1
}

kernel_release=$(tr -d '[:space:]' \
    <"$platform_root/artifacts/kernel/kernel-release")
for kernel_artifact in \
    "$platform_root/artifacts/kernel/Image" \
    "$platform_root/artifacts/kernel/socfpga_agilex5_de25_nano.dtb" \
    "$platform_root/artifacts/kernel/stratix10-soc.ko" \
    "$platform_root/artifacts/kernel/modules-$kernel_release.tar.gz"; do
    verify_release_digest "$kernel_artifact"
done
module_count=$(tar -tzf \
    "$platform_root/artifacts/kernel/modules-$kernel_release.tar.gz" | \
    grep -c '\.ko$')
[[ $module_count -eq 1335 ]] || {
    echo "Release module archive is incomplete: $module_count modules" >&2
    exit 1
}
if ! LC_ALL=C grep -aFq "vermagic=$kernel_release " \
    "$platform_root/artifacts/kernel/stratix10-soc.ko"; then
    echo "FPGA manager module does not match kernel release $kernel_release" >&2
    exit 1
fi
if [[ $build_main == 1 ]]; then
    main=$platform_root/artifacts/main/MiSTer
    [[ -x $main && -s $main.sha256 ]] || {
        echo "ARM64 Main release artifact is incomplete" >&2
        exit 1
    }
    main_digest=$(tr -d '[:space:]' <"$main.sha256" | \
        tr '[:upper:]' '[:lower:]')
    if [[ ! $main_digest =~ ^[0-9a-f]{64}$ ]]; then
        echo "ARM64 Main release digest is invalid: $main.sha256" >&2
        exit 1
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        main_actual_digest=$(sha256sum "$main" | awk '{print $1}')
    else
        main_actual_digest=$(shasum -a 256 "$main" | awk '{print $1}')
    fi
    if [[ $main_digest != "$main_actual_digest" ]]; then
        echo "ARM64 Main release digest does not match: $main" >&2
        exit 1
    fi
fi

if [[ -n $bundle_dir ]]; then
    "$platform_root/scripts/make-update-bundle.sh" "$bundle_dir"
fi
if [[ -n $image_output ]]; then
    "$platform_root/scripts/prepare-sd-image.sh" "$image_base" "$image_output"
fi
printf 'Verified DE25 platform release hash: %s\n' "$expected_hash"
