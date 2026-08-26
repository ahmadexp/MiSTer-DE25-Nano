#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
board=${MISTER_DE25_SSH_TARGET:-terasic@192.168.1.121}
jump=${MISTER_DE25_SSH_JUMP:-user@192.168.1.18}
host_key_alias=${MISTER_DE25_SSH_HOST_KEY_ALIAS:-192.168.1.230}
output=${1:-$platform_root/artifacts/screenshots/de25-$(date +%Y%m%d-%H%M%S).png}
remote_name=remote-$(date +%Y%m%d-%H%M%S)-$$

ssh_args=(-o BatchMode=yes -o ConnectTimeout=10)
[[ -z $jump ]] || ssh_args+=(-J "$jump")
[[ -z $host_key_alias ]] || ssh_args+=(-o "HostKeyAlias=$host_key_alias")

remote_path=$(ssh "${ssh_args[@]}" "$board" \
    "mister-de25-screenshot $remote_name")
if [[ $remote_path != /* ]]; then
    echo "Board returned a non-absolute screenshot path: $remote_path" >&2
    exit 1
fi

printf -v quoted_remote_path '%q' "$remote_path"
mkdir -p "$(dirname "$output")"
partial=$output.partial.$$
trap 'rm -f "$partial"' EXIT

if printf '' | base64 -d >/dev/null 2>&1; then
    decode=(-d)
else
    decode=(-D)
fi
ssh "${ssh_args[@]}" "$board" "base64 $quoted_remote_path" |
    base64 "${decode[@]}" >"$partial"

magic=$(od -An -tx1 -N8 "$partial" | tr -d ' \n')
if [[ $magic != 89504e470d0a1a0a ]]; then
    echo "Retrieved screenshot is not a PNG" >&2
    exit 1
fi

mv -f "$partial" "$output"
trap - EXIT
printf '%s\n' "$output"
