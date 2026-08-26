#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mode=packaged
if [[ ${1:-} == --managed ]]; then
    mode=managed
    shift
fi
output=${1:-}
matrix=${2:-$platform_root/build-matrix.tsv}

if [[ -z $output ]]; then
    echo "Usage: make-runtime-core-catalog.sh [--managed] OUTPUT.tsv [BUILD_MATRIX.tsv]" >&2
    exit 2
fi
if [[ ! -s $matrix ]]; then
    echo "Build matrix is missing: $matrix" >&2
    exit 1
fi

output_dir=$(dirname "$output")
mkdir -p "$output_dir"
temporary=$output.tmp.$$
trap 'rm -f -- "$temporary"' EXIT

printf '# id\trbf\nMENU\tmenu.rbf\n' >"$temporary"
awk -F '\t' -v mode="$mode" '
    BEGIN { seen_id["MENU"] = 1 }
    NR == 1 { next }
    $8 == "packaged" || (mode == "managed" && $10 != "") {
        id = $3
        if (id !~ /^[A-Za-z0-9_.-]+$/) {
            print "Unsafe or missing runtime core ID for " $2 > "/dev/stderr"
            failed = 1
            next
        }
        if ($1 !~ /^_[A-Za-z0-9_.-]+$/ || $10 !~ /\.rbf$/ ||
            $10 ~ /^\// || $10 ~ /(^|\/)\.\.(\/|$)/) {
            print "Unsafe runtime core destination for " $2 > "/dev/stderr"
            failed = 1
            next
        }
        count = split($10, parts, "/")
        destination = $1 "/" parts[count]
        if (seen_id[id]++) {
            print "Duplicate runtime core ID: " id > "/dev/stderr"
            failed = 1
        } else if (seen_destination[destination]++) {
            print "Duplicate runtime core destination: " destination > "/dev/stderr"
            failed = 1
        } else {
            print id "\t" destination
            found = 1
        }
    }
    END { if (failed || !found) exit 1 }
' "$matrix" >>"$temporary"

chmod 0644 "$temporary"
mv -f "$temporary" "$output"
trap - EXIT
