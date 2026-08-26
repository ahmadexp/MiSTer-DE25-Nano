#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$platform_root/.." && pwd)
hps_qdb=
hps_hash_file=
tag=
reuse_existing=0
cores=()

usage() {
    cat <<'EOF' >&2
Usage: build-platform-candidates.sh --hps-qdb FILE --hps-hash FILE --tag TAG
       [--reuse-existing] [CORE ...]

Builds a compatibility-locked candidate set without replacing the packaged
release. CORE may be INPUTTEST, MEMTEST, NES, SNES, MINIMIG, TGFX16, PC110,
PCXT, AO486, APPLE1, or SMS. With no CORE arguments, every catalog-registered core
is built.
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
        --tag)
            [[ $# -ge 2 ]] || usage
            tag=$2
            shift 2
            ;;
        --reuse-existing)
            reuse_existing=1
            shift
            ;;
        --help|-h)
            usage
            ;;
        --*)
            usage
            ;;
        *)
            cores+=("$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')")
            shift
            ;;
    esac
done

[[ -n $hps_qdb && -n $hps_hash_file && -n $tag ]] || usage
[[ $tag =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "Candidate tag contains unsafe characters: $tag" >&2
    exit 1
}
[[ -s $hps_qdb ]] || { echo "HPS partition QDB not found: $hps_qdb" >&2; exit 1; }
[[ -s $hps_hash_file ]] || { echo "HPS hash file not found: $hps_hash_file" >&2; exit 1; }

hps_qdb=$(cd "$(dirname "$hps_qdb")" && printf '%s/%s\n' "$PWD" "$(basename "$hps_qdb")")
hps_hash_file=$(cd "$(dirname "$hps_hash_file")" && printf '%s/%s\n' "$PWD" "$(basename "$hps_hash_file")")
case $hps_qdb in
    "$workspace_root"/*) ;;
    *) echo "HPS partition QDB must be inside the workspace" >&2; exit 1 ;;
esac
case $hps_hash_file in
    "$workspace_root"/*) ;;
    *) echo "HPS hash file must be inside the workspace" >&2; exit 1 ;;
esac

expected_hash=$(tr -d '[:space:]' <"$hps_hash_file" | tr '[:lower:]' '[:upper:]')
[[ $expected_hash =~ ^[0-9A-F]{64}$ ]] || {
    echo "Invalid HPS I/O hash: $hps_hash_file" >&2
    exit 1
}

if [[ ${#cores[@]} -eq 0 ]]; then
    cores=(INPUTTEST MEMTEST NES SNES MINIMIG TGFX16 PC110 PCXT AO486 APPLE1 SMS)
fi

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

candidate_valid() {
    local output=$1 candidate_hash expected_digest actual_digest
    [[ -s $output && -s $output.hps-io-hash && -s $output.sha256 ]] || return 1
    candidate_hash=$(tr -d '[:space:]' <"$output.hps-io-hash" | \
        tr '[:lower:]' '[:upper:]')
    [[ $candidate_hash == "$expected_hash" ]] || return 1
    expected_digest=$(tr -d '[:space:]' <"$output.sha256" | \
        tr '[:upper:]' '[:lower:]')
    [[ $expected_digest =~ ^[0-9a-f]{64}$ ]] || return 1
    actual_digest=$(hash_file "$output")
    [[ $actual_digest == "$expected_digest" ]]
}

candidate_parameters() {
    case $1 in
        INPUTTEST)
            printf '%s\034%s\034%s\n' scripts/build-inputtest.sh \
                artifacts/inputtest/InputTest_"$tag".rbf DE25_INPUTTEST_OUTPUT_RBF
            ;;
        MEMTEST)
            printf '%s\034%s\034%s\n' scripts/build-memtest.sh \
                artifacts/memtest/MemTest_"$tag".rbf DE25_MEMTEST_OUTPUT_RBF
            ;;
        NES)
            printf '%s\034%s\034%s\n' scripts/build-nes.sh \
                artifacts/nes/NES_"$tag".rbf DE25_NES_OUTPUT_RBF
            ;;
        SNES)
            printf '%s\034%s\034%s\n' scripts/build-snes.sh \
                artifacts/snes/SNES_"$tag".rbf DE25_SNES_OUTPUT_RBF
            ;;
        MINIMIG)
            printf '%s\034%s\034%s\n' scripts/build-minimig.sh \
                artifacts/minimig/Minimig_"$tag".rbf DE25_MINIMIG_OUTPUT_RBF
            ;;
        TGFX16)
            printf '%s\034%s\034%s\n' scripts/build-tgfx16.sh \
                artifacts/tgfx16/TurboGrafx16_"$tag".rbf DE25_TGFX16_OUTPUT_RBF
            ;;
        PC110)
            printf '%s\034%s\034%s\n' scripts/build-pc110.sh \
                artifacts/pc110/IBM_PC110_"$tag".rbf DE25_PC110_OUTPUT_RBF
            ;;
        PCXT)
            printf '%s\034%s\034%s\n' scripts/build-pcxt.sh \
                artifacts/pcxt/PCXT_"$tag".rbf DE25_PCXT_OUTPUT_RBF
            ;;
        AO486)
            printf '%s\034%s\034%s\n' scripts/build-ao486.sh \
                artifacts/ao486/AO486_"$tag".rbf DE25_AO486_OUTPUT_RBF
            ;;
        APPLE1)
            printf '%s\034%s\034%s\n' scripts/build-apple1.sh \
                artifacts/apple1/Apple-I_"$tag".rbf DE25_APPLE1_OUTPUT_RBF
            ;;
        SMS)
            printf '%s\034%s\034%s\n' scripts/build-sms.sh \
                artifacts/sms/SMS_"$tag".rbf DE25_SMS_OUTPUT_RBF
            ;;
        *)
            echo "Unsupported candidate core: $1" >&2
            return 1
            ;;
    esac
}

export DE25_HPS_PARTITION_MODE=reuse
export DE25_HPS_PARTITION_QDB=$hps_qdb
export DE25_EXPECTED_HPS_IO_HASH_FILE=$hps_hash_file

manifest_dir=$platform_root/artifacts/candidates/$tag
mkdir -p "$manifest_dir"
manifest_new=$manifest_dir/manifest.tsv.new
printf '# core\tartifact\tsha256\thps_io_hash\n' >"$manifest_new"

for core in "${cores[@]}"; do
    IFS=$'\034' read -r build_script artifact output_variable <<< \
        "$(candidate_parameters "$core")"
    output=$platform_root/$artifact
    if [[ $reuse_existing == 1 ]] && candidate_valid "$output"; then
        echo "Reusing verified $core candidate: $output"
    else
        mkdir -p "$(dirname "$output")"
        echo "Building $core candidate: $output"
        env "$output_variable=$output" "$platform_root/$build_script"
    fi
    candidate_valid "$output" || {
        echo "Candidate verification failed: $output" >&2
        exit 1
    }
    printf '%s\t%s\t%s\t%s\n' "$core" "$artifact" \
        "$(tr -d '[:space:]' <"$output.sha256")" "$expected_hash" \
        >>"$manifest_new"
done

mv -f "$manifest_new" "$manifest_dir/manifest.tsv"
echo "Verified candidate set: $manifest_dir/manifest.tsv"
