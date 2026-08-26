#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "Usage: make-hps-first-rbf.sh INPUT.sof RUNTIME.rbf HPS_BOOTLOADER.hex [PHASE_PREFIX]" >&2
    exit 2
fi

input_sof=$1
runtime_rbf=$2
hps_bootloader=$3
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
phase_prefix=${4:-${runtime_rbf%.rbf}_HPS_FIRST}
phase1_rbf=$phase_prefix.hps.rbf
phase2_rbf=$phase_prefix.core.rbf
legacy_jtag_sof=$phase_prefix.jtag.sof
compatibility_file=$runtime_rbf.hps-io-hash
digest_file=$runtime_rbf.sha256

for input in "$input_sof" "$hps_bootloader"; do
    if [[ ! -f $input ]]; then
        echo "HPS-first input not found: $input" >&2
        exit 1
    fi
done

mkdir -p "$(dirname "$runtime_rbf")"
rm -f "$phase1_rbf" "$phase2_rbf" "$phase_prefix.rbf" "$legacy_jtag_sof"
# Agilex 5 HPS-first configuration is a two-phase transaction. The initial
# JTAG image is the split phase-1 *.hps.rbf containing the HPS I/O shell and
# SPL. Linux loads the matching phase-2 core RBF after the HPS has booted.
# A SOF with an embedded SPL is not a substitute for the phase-1 RBF.
quartus_pfg -c "$input_sof" "$phase_prefix.rbf" \
    -o "hps_path=$hps_bootloader" -o hps=1
test -s "$phase1_rbf"
test -s "$phase2_rbf"
install -m 0644 "$phase2_rbf" "$runtime_rbf"

hps_io_hash=$($script_dir/extract-hps-io-hash.sh "$runtime_rbf")
expected_hash_file=${DE25_EXPECTED_HPS_IO_HASH_FILE:-$script_dir/../artifacts/recovery-078a/platform.hps-io-hash}
if [[ ! -s $expected_hash_file ]]; then
    echo "Expected DE25 HPS I/O hash is missing: $expected_hash_file" >&2
    exit 1
fi
expected_hash=$(tr -d '[:space:]' <"$expected_hash_file" | tr '[:lower:]' '[:upper:]')
if [[ ! $expected_hash =~ ^[0-9A-F]{64}$ ]]; then
    echo "Expected DE25 HPS I/O hash is invalid: $expected_hash_file" >&2
    exit 1
fi
if [[ $hps_io_hash != "$expected_hash" ]]; then
    rm -f "$runtime_rbf" "$compatibility_file" "$digest_file"
    echo "Generated runtime RBF is incompatible with the DE25 boot platform:" >&2
    echo "  Expected:  $expected_hash" >&2
    echo "  Generated: $hps_io_hash" >&2
    exit 1
fi
printf '%s\n' "$hps_io_hash" >"$compatibility_file"
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$runtime_rbf" | awk '{print $1}' >"$digest_file"
else
    shasum -a 256 "$runtime_rbf" | awk '{print $1}' >"$digest_file"
fi

echo "HPS-first phase 1: $phase1_rbf"
echo "Runtime core phase 2: $runtime_rbf"
echo "JTAG cold-boot image: $phase1_rbf"
echo "HPS I/O compatibility: $hps_io_hash"
echo "Runtime core SHA-256: $(<"$digest_file")"
