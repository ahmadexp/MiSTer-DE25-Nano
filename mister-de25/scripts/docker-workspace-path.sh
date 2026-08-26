#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: docker-workspace-path.sh WORKSPACE_ROOT PATH" >&2
    exit 2
fi

workspace_root=$(cd "$1" && pwd)
input_path=$2

case $input_path in
    */../*|*/..|*/./*|*/.)
        echo "Docker input must not contain dot path segments: $input_path" >&2
        exit 1
        ;;
esac

case $input_path in
    /work/PC110-Mister/*)
        printf '%s\n' "$input_path"
        ;;
    "$workspace_root"/*)
        printf '/work/PC110-Mister/%s\n' "${input_path#"$workspace_root/"}"
        ;;
    *)
        echo "Docker input must be inside the workspace: $input_path" >&2
        exit 1
        ;;
esac
