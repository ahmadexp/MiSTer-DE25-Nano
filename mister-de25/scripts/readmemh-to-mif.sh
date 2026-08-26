#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 INPUT.hex DEPTH OUTPUT.mif" >&2
    exit 2
fi

input=$1
depth=$2
output=$3

if [[ ! $depth =~ ^[1-9][0-9]*$ ]]; then
    echo "depth must be a positive decimal integer" >&2
    exit 2
fi

tmp=${output}.tmp
trap 'rm -f "$tmp"' EXIT

awk -v depth="$depth" '
    function hex_value(text, value, digit, i) {
        value = 0
        text = toupper(text)
        for (i = 1; i <= length(text); ++i) {
            digit = index("0123456789ABCDEF", substr(text, i, 1)) - 1
            if (digit < 0)
                return -1
            value = value * 16 + digit
        }
        return value
    }
    BEGIN {
        print "WIDTH=8;"
        print "DEPTH=" depth ";"
        print "ADDRESS_RADIX=HEX;"
        print "DATA_RADIX=HEX;"
        print "CONTENT BEGIN"
    }
    {
        sub(/\/\/.*/, "")
        for (i = 1; i <= NF; ++i) {
            token = $i
            if (token ~ /^@/) {
                sub(/^@/, "", token)
                address = hex_value(token)
                next
            }
            if (token !~ /^[[:xdigit:]]+$/) {
                printf "invalid readmemh token %s\n", token > "/dev/stderr"
                exit 1
            }
            if (address >= depth) {
                printf "input exceeds declared depth %d\n", depth > "/dev/stderr"
                exit 1
            }
            printf "%X : %02X;\n", address, hex_value(token)
            ++address
        }
    }
    END {
        if (address < depth)
            printf "[%X..%X] : 00;\n", address, depth - 1
        print "END;"
    }
' "$input" > "$tmp"

mv "$tmp" "$output"
trap - EXIT
