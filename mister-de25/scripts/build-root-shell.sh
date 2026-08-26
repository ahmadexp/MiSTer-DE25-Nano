#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root_qdb=$platform_root/artifacts/shell/de25_mister_root_078a_final.qdb

if [[ ${DE25_ENABLE_EXPERIMENTAL_RESERVED_CORE:-} != 1 ]]; then
    cat >&2 <<'EOF'
The Reserved Core QDB flow is experimental and is not used for releases.
It currently fails Agilex 5 clock placement for the required core boundary.
Production builds create complete HPS-first RBFs from the common source shell.
Set DE25_ENABLE_EXPERIMENTAL_RESERVED_CORE=1 only for fitter research.
EOF
    exit 2
fi

mkdir -p "$(dirname "$root_qdb")"
rm -f "$root_qdb"
DE25_ROOT_SHELL_MODE=source \
    "$platform_root/scripts/build-menu.sh"
test -s "$root_qdb"

echo "Reusable DE25 root shell: $root_qdb"
