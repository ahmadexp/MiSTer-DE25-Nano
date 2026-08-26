#!/bin/sh
set -eu

device=${1:-/dev/ttyUSB0}
command=${2:-}
seconds=${3:-3}

stty -F "$device" 115200 cs8 -cstopb -parenb raw -echo
timeout "$seconds" cat "$device" &
reader=$!
sleep 0.2
printf '\r%s\r' "$command" >"$device"
wait "$reader" || true
