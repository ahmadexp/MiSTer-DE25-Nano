#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF' >&2
Usage: make-qspi-jic-from-hps-rbf.sh HPS_PHASE1.rbf OUTPUT.jic

Packages an existing Agilex 5 HPS-first phase-1 RBF as a DE25-Nano ASx4 QSPI
JIC, then verifies that the output preserves the input HPS I/O hash. This is
used to construct a recovery JIC when the original Quartus SOF was not kept.
EOF
}

if [[ $# -ne 2 ]]; then
    usage
    exit 2
fi

phase1_rbf=$1
output_jic=$2
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ ! -s $phase1_rbf ]]; then
    echo "HPS-first phase-1 RBF is missing or empty: $phase1_rbf" >&2
    exit 1
fi
if [[ -e $output_jic ]]; then
    echo "Refusing to overwrite existing output: $output_jic" >&2
    exit 1
fi

input_hash=$($script_dir/extract-hps-io-hash.sh "$phase1_rbf")
temporary=${output_jic%.jic}.tmp.$$.jic
cleanup() {
    rm -f -- "$temporary"
}
trap cleanup EXIT HUP INT TERM

quartus_pfg -c "$phase1_rbf" "$temporary" \
    -o device=MT25QU128 -o flash_loader=A5EB013BB23B -o mode=ASX4
test -s "$temporary"
output_hash=$($script_dir/extract-hps-io-hash.sh "$temporary")
if [[ $output_hash != "$input_hash" ]]; then
    echo "Generated recovery JIC changed the HPS I/O hash:" >&2
    echo "  phase 1: $input_hash" >&2
    echo "  JIC:     $output_hash" >&2
    exit 1
fi

mv "$temporary" "$output_jic"
trap - EXIT HUP INT TERM
echo "Recovery QSPI JIC: $output_jic"
echo "HPS I/O hash: $output_hash"
