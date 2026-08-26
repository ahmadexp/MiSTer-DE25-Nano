#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/mister-de25-watchdog-test.XXXXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

helper=$platform_root/sw/mister-de25-watchdog-run
watchdog=$test_root/watchdog
timeout_path=$test_root/timeout
nowayout_path=$test_root/nowayout
command_marker=$test_root/command-ran

: >"$watchdog"
: >"$timeout_path"
printf '0\n' >"$nowayout_path"
MISTER_DE25_WATCHDOG_DEVICE=$watchdog \
MISTER_DE25_WATCHDOG_ALLOW_REGULAR=1 \
MISTER_DE25_WATCHDOG_TIMEOUT=73 \
MISTER_DE25_WATCHDOG_TIMEOUT_PATH=$timeout_path \
MISTER_DE25_WATCHDOG_NOWAYOUT_PATH=$nowayout_path \
    "$helper" sh -c "printf ran >'$command_marker'"

grep -qx 73 "$timeout_path"
grep -qx ran "$command_marker"
[[ $(od -An -tx1 -v "$watchdog" | tr -d ' \n') == 0056 ]]

: >"$watchdog"
if MISTER_DE25_WATCHDOG_DEVICE=$watchdog \
   MISTER_DE25_WATCHDOG_ALLOW_REGULAR=1 \
   MISTER_DE25_WATCHDOG_TIMEOUT_PATH=$timeout_path \
   MISTER_DE25_WATCHDOG_NOWAYOUT_PATH=$nowayout_path \
   MISTER_DE25_WATCHDOG_FAILURE_ACTION=return \
       "$helper" sh -c 'exit 23' >/dev/null 2>&1; then
    echo "FAIL: watchdog wrapper reported a failed command as successful" >&2
    exit 1
else
    status=$?
fi
[[ $status -eq 23 ]]
[[ $(od -An -tx1 -v "$watchdog" | tr -d ' \n') == 00 ]]

if MISTER_DE25_WATCHDOG_DEVICE=$test_root/missing \
   MISTER_DE25_WATCHDOG_ALLOW_REGULAR=0 \
       "$helper" true >/dev/null 2>&1; then
    echo "FAIL: watchdog wrapper accepted a missing hardware watchdog" >&2
    exit 1
fi

echo "PASS: FPGA transaction watchdog completes only after success"
