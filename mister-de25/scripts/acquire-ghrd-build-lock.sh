#!/usr/bin/env bash

# Source this file from a build script. The open descriptor remains held until
# that build exits, protecting the shared disposable GHRD and generated HPS IP
# from concurrent Quartus jobs.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    echo "acquire-ghrd-build-lock.sh must be sourced by a build script" >&2
    exit 2
fi

if ! command -v flock >/dev/null 2>&1; then
    echo "flock is required to serialize DE25 HPS builds" >&2
    exit 1
fi

de25_ghrd_lock_file=$workspace_root/de25-nano/vendor/.de25-ghrd-build.lock
mkdir -p "$(dirname "$de25_ghrd_lock_file")"
exec 9>"$de25_ghrd_lock_file"
flock 9
