#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/mister-de25-selector-test.XXXXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

fat=$test_root/fat
catalog=$test_root/cores.tsv
mock=$test_root/test-rbf
request=$test_root/core.request
request_dir=$test_root/request
log=$test_root/actions.log
mkdir -p "$fat/_Console"
mkdir -p "$request_dir"
printf '# id\trbf\nMENU\tmenu.rbf\nNES\t_Console/NES.rbf\n' >"$catalog"
for rbf in "$fat/menu.rbf" "$fat/_Console/NES.rbf"; do
    printf 'rbf\n' >"$rbf"
    printf 'hash\n' >"$rbf.hps-io-hash"
    printf 'digest\n' >"$rbf.sha256"
done
cat >"$mock" <<EOF
#!/usr/bin/env bash
printf '%s\t%s\n' "\$1" "\$2" >>'$log'
EOF
chmod +x "$mock"

MISTER_DE25_FAT_ROOT=$fat \
MISTER_DE25_CORE_CATALOG=$catalog \
MISTER_DE25_TEST_HELPER=$mock \
    "$platform_root/sw/mister-de25-select-core" NES
expected_line=$(printf '%s\t%s' "$fat/_Console/NES.rbf" "$fat/menu.rbf")
grep -Fqx "$expected_line" "$log"

if MISTER_DE25_FAT_ROOT=$fat \
   MISTER_DE25_CORE_CATALOG=$catalog \
   MISTER_DE25_TEST_HELPER=$mock \
       "$platform_root/sw/mister-de25-select-core" UNKNOWN >/dev/null 2>&1; then
    echo "FAIL: selector accepted an unknown core ID" >&2
    exit 1
fi
printf '# id\trbf\nBAD\t../outside.rbf\n' >"$catalog"
if MISTER_DE25_FAT_ROOT=$fat \
   MISTER_DE25_CORE_CATALOG=$catalog \
   MISTER_DE25_TEST_HELPER=$mock \
       "$platform_root/sw/mister-de25-select-core" BAD >/dev/null 2>&1; then
    echo "FAIL: selector accepted a traversal path" >&2
    exit 1
fi

cat >"$test_root/selector" <<EOF
#!/usr/bin/env bash
printf 'request:%s\n' "\$*" >>'$log'
EOF
chmod +x "$test_root/selector"
printf 'NES\n' >"$request"
MISTER_DE25_CORE_REQUEST=$request \
MISTER_DE25_CORE_SELECTOR=$test_root/selector \
    "$platform_root/sw/mister-de25-process-core-request"
grep -qx 'request:NES' "$log"
[[ ! -e $request ]]

ln -s /etc/passwd "$request"
if MISTER_DE25_CORE_REQUEST=$request \
   MISTER_DE25_CORE_SELECTOR=$test_root/selector \
       "$platform_root/sw/mister-de25-process-core-request" >/dev/null 2>&1; then
    echo "FAIL: request worker accepted a symlink" >&2
    exit 1
fi
[[ ! -e $request && ! -L $request ]]

MISTER_DE25_REQUEST_DIR=$request_dir \
MISTER_DE25_CORE_CATALOG=$catalog \
    "$platform_root/sw/mister-de25-core" NES >/dev/null
grep -qx $'LOAD\tNES' "$request_dir/core.request"
MISTER_DE25_CORE_CATALOG=$catalog \
    "$platform_root/sw/mister-de25-core" --list | grep -qx BAD

echo "PASS: remote core requests are restricted to the generated catalog"
