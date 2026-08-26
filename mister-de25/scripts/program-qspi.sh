#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF' >&2
Usage: program-qspi.sh --device INDEX --confirm PROGRAM JIC RUNTIME_RBF

Programs and verifies the DE25-Nano QSPI HPS-first image only after proving
that the JIC and runtime RBF carry the same HPS I/O hash. This command does not
install the runtime RBF on an SD card and does not power-cycle the board.
EOF
}

if [[ $# -ne 6 || $1 != --device || $3 != --confirm ]]; then
    usage
    exit 2
fi

device_index=$2
confirmation=$4
jic=$5
runtime_rbf=$6

if [[ ! $device_index =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid JTAG device index: $device_index" >&2
    exit 2
fi
if [[ $confirmation != PROGRAM ]]; then
    echo "Refusing QSPI programming without the literal --confirm PROGRAM" >&2
    exit 2
fi
for input in "$jic" "$runtime_rbf"; do
    if [[ ! -s $input ]]; then
        echo "Programming input is missing or empty: $input" >&2
        exit 1
    fi
done

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
jic_hash=$("$platform_root/scripts/extract-hps-io-hash.sh" "$jic")
runtime_hash=$("$platform_root/scripts/extract-hps-io-hash.sh" "$runtime_rbf")
if [[ $jic_hash != "$runtime_hash" ]]; then
    echo "Refusing unmatched QSPI and runtime images:" >&2
    echo "  JIC: $jic_hash" >&2
    echo "  RBF: $runtime_hash" >&2
    exit 1
fi

echo "About to program and verify QSPI on JTAG device $device_index"
echo "JIC: $jic"
echo "Matched runtime: $runtime_rbf"
echo "HPS I/O hash: $jic_hash"
jtagconfig
quartus_pgm -m jtag -o "ibpv;$jic@$device_index"

echo "QSPI programming and verification completed."
echo "Use mister-de25-platform-migration to install this RBF across a reboot:"
echo "  $runtime_rbf"
echo "  HPS I/O hash: $jic_hash"
