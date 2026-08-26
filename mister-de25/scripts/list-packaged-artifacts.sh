#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mode=packaged
if [[ ${1:-} == --managed ]]; then
    mode=managed
    shift
fi
if [[ $# -gt 1 ]]; then
    echo "Usage: list-packaged-artifacts.sh [--managed] [BUILD_MATRIX.tsv]" >&2
    exit 2
fi
matrix=${1:-$platform_root/build-matrix.tsv}

if [[ ! -s $matrix ]]; then
    echo "Build matrix is missing: $matrix" >&2
    exit 1
fi

awk -F '\t' -v mode="$mode" '
    NR == 1 { next }
    $8 == "packaged" || (mode == "managed" && $10 != "") {
        if ($1 !~ /^_[A-Za-z0-9_.-]+$/) {
            print "Unsafe packaged category: " $1 > "/dev/stderr"
            failed = 1
        } else if ($10 == "" || $10 !~ /\.rbf$/ || $10 ~ /^\// ||
                   $10 ~ /(^|\/)\.\.(\/|$)/) {
            print "Unsafe packaged artifact: " $10 > "/dev/stderr"
            failed = 1
        } else {
            count = split($10, path, "/")
            destination = $1 "/" path[count]
            if (seen_destination[destination]++) {
                print "Duplicate packaged destination: " destination > "/dev/stderr"
                failed = 1
            } else {
                print $1 "\t" $10
                found = 1
            }
        }
    }
    END {
        if (failed || !found) exit 1
    }
' "$matrix"
