#!/usr/bin/env bash
set -euo pipefail

minimum_major=${1:-24}
minimum_minor=${2:-2}

if ! command -v quartus_sh >/dev/null 2>&1; then
    echo "quartus_sh is not available" >&2
    exit 1
fi

version=$(quartus_sh --version 2>&1 | awk '
    match($0, /[0-9]+\.[0-9]+/) {
        print substr($0, RSTART, RLENGTH)
        exit
    }
')

if [[ -z $version ]]; then
    echo "Unable to determine the Quartus version" >&2
    exit 1
fi

major=${version%%.*}
minor=${version#*.}

if (( major < minimum_major || (major == minimum_major && minor < minimum_minor) )); then
    echo "Quartus $minimum_major.$minimum_minor or newer is required; found $version" >&2
    exit 1
fi

echo "PASS: Quartus $version satisfies the $minimum_major.$minimum_minor minimum"
