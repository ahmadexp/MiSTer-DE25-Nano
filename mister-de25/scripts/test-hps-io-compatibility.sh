#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/mister-de25-compat-test.XXXXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

expected=078A3C543CF82A135C3914508B7426E499FBBB92A453C102F9D8F198BF3EFFF7
different=178A3C543CF82A135C3914508B7426E499FBBB92A453C102F9D8F198BF3EFFF7
rbf=$test_root/core.rbf
platform=$test_root/platform.hash
printf 'test rbf\n' >"$rbf"
printf '%s\n' "$expected" >"$rbf.hps-io-hash"
printf '%s\n' "$expected" >"$platform"
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$rbf" | awk '{print $1}' >"$rbf.sha256"
else
    shasum -a 256 "$rbf" | awk '{print $1}' >"$rbf.sha256"
fi

MISTER_DE25_HPS_IO_HASH=$platform \
    "$platform_root/sw/mister-de25-check-rbf" "$rbf" >/dev/null

printf '%s\n' "$different" >"$rbf.hps-io-hash"
if MISTER_DE25_HPS_IO_HASH=$platform \
    "$platform_root/sw/mister-de25-check-rbf" "$rbf" >/dev/null 2>&1; then
    echo "FAIL: compatibility checker accepted a mismatched RBF" >&2
    exit 1
fi

: >"$rbf.hps-io-hash"
if MISTER_DE25_HPS_IO_HASH=$platform \
    "$platform_root/sw/mister-de25-check-rbf" "$rbf" >/dev/null 2>&1; then
    echo "FAIL: compatibility checker accepted missing metadata" >&2
    exit 1
fi

printf 'invalid\n' >"$rbf.hps-io-hash"
if MISTER_DE25_HPS_IO_HASH=$platform \
    "$platform_root/sw/mister-de25-check-rbf" "$rbf" >/dev/null 2>&1; then
    echo "FAIL: compatibility checker accepted malformed metadata" >&2
    exit 1
fi

printf '%s\n' "$expected" >"$rbf.hps-io-hash"
printf 'modified after packaging\n' >>"$rbf"
if MISTER_DE25_HPS_IO_HASH=$platform \
    "$platform_root/sw/mister-de25-check-rbf" "$rbf" >/dev/null 2>&1; then
    echo "FAIL: compatibility checker accepted a stale RBF digest" >&2
    exit 1
fi

rm -f "$rbf.sha256"
if MISTER_DE25_HPS_IO_HASH=$platform \
    "$platform_root/sw/mister-de25-check-rbf" "$rbf" >/dev/null 2>&1; then
    echo "FAIL: compatibility checker accepted missing RBF digest metadata" >&2
    exit 1
fi

printf 'invalid\n' >"$rbf.sha256"
if MISTER_DE25_HPS_IO_HASH=$platform \
    "$platform_root/sw/mister-de25-check-rbf" "$rbf" >/dev/null 2>&1; then
    echo "FAIL: compatibility checker accepted malformed RBF digest metadata" >&2
    exit 1
fi

echo "PASS: HPS I/O compatibility and RBF payload metadata are fail-safe"
