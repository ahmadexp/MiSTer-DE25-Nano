#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/Main_MiSTer"}
image=${MISTER_MAIN_IMAGE:-mister-main-aarch64:22.04}
output=${MISTER_DE25_MAIN_OUTPUT:-$root_dir/artifacts/main/MiSTer}

docker build \
  --platform linux/arm64 \
  -t "$image" \
  -f "$root_dir/docker/Dockerfile.main-aarch64" \
  "$root_dir"

docker run --rm \
  --platform linux/arm64 \
  -v "$source_dir:/src" \
  -w /src \
  "$image" \
  make ARCH=aarch64 MAKEFLAGS=-j2 -j2

mkdir -p "$(dirname "$output")"
install -m 0755 "$source_dir/bin/MiSTer" "$output.new"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$output.new" | awk '{print $1}' >"$output.sha256.new"
else
  shasum -a 256 "$output.new" | awk '{print $1}' >"$output.sha256.new"
fi
mv -f "$output.new" "$output"
mv -f "$output.sha256.new" "$output.sha256"
echo "DE25-Nano Main artifact: $output"
