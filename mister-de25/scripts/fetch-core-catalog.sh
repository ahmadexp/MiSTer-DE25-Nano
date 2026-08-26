#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
catalog=${1:-"$root_dir/core-catalog.tsv"}
destination=${2:-"$root_dir/upstream/cores"}

mkdir -p "$destination"

while IFS=$'\t' read -r tier name repository revision purpose; do
  if [[ -z "$tier" || "$tier" == \#* ]]; then
    continue
  fi

  if [[ ! $revision =~ ^[0-9a-f]{40}$ ]]; then
    echo "Invalid locked revision for $name: $revision" >&2
    exit 1
  fi

  core_dir="$destination/$name"
  if [[ -d "$core_dir/.git" ]]; then
    if [[ -n $(git -C "$core_dir" status --porcelain) ]]; then
      echo "Refusing to replace a modified core checkout: $core_dir" >&2
      exit 1
    fi
    git -C "$core_dir" fetch --depth 1 origin "$revision"
  else
    git init -q "$core_dir"
    git -C "$core_dir" remote add origin "$repository"
    git -C "$core_dir" fetch --depth 1 origin "$revision"
  fi
  git -C "$core_dir" checkout -q --detach FETCH_HEAD

  actual_revision=$(git -C "$core_dir" rev-parse HEAD)
  if [[ $actual_revision != "$revision" ]]; then
    echo "Core revision mismatch for $name: $actual_revision" >&2
    exit 1
  fi

  printf '%s\t%s\t%s\t%s\n' "$tier" "$name" "$revision" "$purpose"
done < "$catalog"
