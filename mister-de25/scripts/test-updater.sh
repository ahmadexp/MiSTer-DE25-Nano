#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/mister-de25-updater-test.XXXXXXXX")

cleanup() {
    rm -rf -- "$test_root"
}
trap cleanup EXIT

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

file_size() {
    if stat -c %s "$1" >/dev/null 2>&1; then
        stat -c %s "$1"
    else
        stat -f %z "$1"
    fi
}

bundle=$test_root/bundle
fat=$test_root/fat
system=$test_root/system
mkdir -p "$bundle/payload" "$fat" "$system"
cp "$platform_root/sw/mister-de25-load" "$bundle/payload/loader"
cp "$platform_root/sw/mister-de25-bridge" "$bundle/payload/bridge"
cat >"$bundle/manifest.tsv" <<EOF
# sha256	size	mode	scope	destination	payload
$(hash_file "$bundle/payload/loader")	$(file_size "$bundle/payload/loader")	0755	fat	Scripts/loader	loader
$(hash_file "$bundle/payload/bridge")	$(file_size "$bundle/payload/bridge")	0755	fat	Scripts/bridge	bridge
EOF

DE25_FAT_ROOT=$fat DE25_SYS_ROOT=$system \
    "$platform_root/sw/update_de25.sh" "$bundle" >/dev/null
cmp "$platform_root/sw/mister-de25-load" "$fat/Scripts/loader"
cmp "$platform_root/sw/mister-de25-bridge" "$fat/Scripts/bridge"

DE25_FAT_ROOT=$fat DE25_SYS_ROOT=$system \
    "$platform_root/sw/update_de25.sh" "$bundle" >/dev/null
cmp "$platform_root/sw/mister-de25-load" "$fat/Scripts/loader.previous"
cmp "$platform_root/sw/mister-de25-bridge" "$fat/Scripts/bridge.previous"

# Force failure on the second install target after the first file switches.
# The transaction trap must restore the first target from its backup.
printf 'known previous contents\n' >"$fat/rollback-target"
mkdir -p "$fat/fail-target"
cat >"$bundle/manifest.tsv" <<EOF
# sha256	size	mode	scope	destination	payload
$(hash_file "$bundle/payload/loader")	$(file_size "$bundle/payload/loader")	0755	fat	rollback-target	loader
$(hash_file "$bundle/payload/bridge")	$(file_size "$bundle/payload/bridge")	0755	fat	fail-target	bridge
EOF
if DE25_FAT_ROOT=$fat DE25_SYS_ROOT=$system \
    "$platform_root/sw/update_de25.sh" "$bundle" >/dev/null 2>&1; then
    echo "FAIL: updater accepted a directory as an install target" >&2
    exit 1
fi
grep -qx 'known previous contents' "$fat/rollback-target"

# A root-owned updater must never follow an installed directory or backup
# symlink outside either selected installation tree.
outside=$test_root/outside
mkdir -p "$outside"
ln -s "$outside" "$fat/escape"
cat >"$bundle/manifest.tsv" <<EOF
# sha256	size	mode	scope	destination	payload
$(hash_file "$bundle/payload/loader")	$(file_size "$bundle/payload/loader")	0755	fat	escape/loader	loader
EOF
if DE25_FAT_ROOT=$fat DE25_SYS_ROOT=$system \
    "$platform_root/sw/update_de25.sh" "$bundle" >/dev/null 2>&1; then
    echo "FAIL: updater followed a symlinked destination directory" >&2
    exit 1
fi
test ! -e "$outside/loader"

printf 'installed target\n' >"$fat/symlink-backup-target"
printf 'outside sentinel\n' >"$outside/sentinel"
ln -s "$outside/sentinel" "$fat/symlink-backup-target.previous"
cat >"$bundle/manifest.tsv" <<EOF
# sha256	size	mode	scope	destination	payload
$(hash_file "$bundle/payload/loader")	$(file_size "$bundle/payload/loader")	0755	fat	symlink-backup-target	loader
EOF
if DE25_FAT_ROOT=$fat DE25_SYS_ROOT=$system \
    "$platform_root/sw/update_de25.sh" "$bundle" >/dev/null 2>&1; then
    echo "FAIL: updater followed a symlinked backup destination" >&2
    exit 1
fi
grep -qx 'installed target' "$fat/symlink-backup-target"
grep -qx 'outside sentinel' "$outside/sentinel"

# RBF payloads require a matching sidecar and must match the installed QSPI
# phase hash before the transaction changes any target.
expected=078A3C543CF82A135C3914508B7426E499FBBB92A453C102F9D8F198BF3EFFF7
different=178A3C543CF82A135C3914508B7426E499FBBB92A453C102F9D8F198BF3EFFF7
mkdir -p "$system/etc/mister-de25"
printf '%s\n' "$expected" >"$system/etc/mister-de25/hps-io-hash"
printf 'new rbf\n' >"$bundle/payload/test.rbf"
printf '%s\n' "$expected" >"$bundle/payload/test.rbf.hps-io-hash"
hash_file "$bundle/payload/test.rbf" >"$bundle/payload/test.rbf.sha256"
cat >"$bundle/manifest.tsv" <<EOF
# sha256	size	mode	scope	destination	payload
$(hash_file "$bundle/payload/test.rbf")	$(file_size "$bundle/payload/test.rbf")	0644	fat	_Utility/test.rbf	test.rbf
$(hash_file "$bundle/payload/test.rbf.hps-io-hash")	$(file_size "$bundle/payload/test.rbf.hps-io-hash")	0644	fat	_Utility/test.rbf.hps-io-hash	test.rbf.hps-io-hash
$(hash_file "$bundle/payload/test.rbf.sha256")	$(file_size "$bundle/payload/test.rbf.sha256")	0644	fat	_Utility/test.rbf.sha256	test.rbf.sha256
EOF
DE25_FAT_ROOT=$fat DE25_SYS_ROOT=$system \
    "$platform_root/sw/update_de25.sh" "$bundle" >/dev/null
grep -qx 'new rbf' "$fat/_Utility/test.rbf"
grep -qx "$expected" "$fat/_Utility/test.rbf.hps-io-hash"
cmp "$bundle/payload/test.rbf.sha256" "$fat/_Utility/test.rbf.sha256"

printf 'installed rbf\n' >"$fat/_Utility/test.rbf"
printf '%s\n' "$expected" >"$fat/_Utility/test.rbf.hps-io-hash"
hash_file "$fat/_Utility/test.rbf" >"$fat/_Utility/test.rbf.sha256"
printf '%s\n' "$different" >"$bundle/payload/test.rbf.hps-io-hash"
cat >"$bundle/manifest.tsv" <<EOF
# sha256	size	mode	scope	destination	payload
$(hash_file "$bundle/payload/test.rbf")	$(file_size "$bundle/payload/test.rbf")	0644	fat	_Utility/test.rbf	test.rbf
$(hash_file "$bundle/payload/test.rbf.hps-io-hash")	$(file_size "$bundle/payload/test.rbf.hps-io-hash")	0644	fat	_Utility/test.rbf.hps-io-hash	test.rbf.hps-io-hash
$(hash_file "$bundle/payload/test.rbf.sha256")	$(file_size "$bundle/payload/test.rbf.sha256")	0644	fat	_Utility/test.rbf.sha256	test.rbf.sha256
EOF
if DE25_FAT_ROOT=$fat DE25_SYS_ROOT=$system \
    "$platform_root/sw/update_de25.sh" "$bundle" >/dev/null 2>&1; then
    echo "FAIL: updater accepted an RBF with a mismatched HPS I/O hash" >&2
    exit 1
fi
grep -qx 'installed rbf' "$fat/_Utility/test.rbf"
grep -qx "$expected" "$fat/_Utility/test.rbf.hps-io-hash"

# A matching HPS label cannot authorize different RBF bytes.
printf '%s\n' "$expected" >"$bundle/payload/test.rbf.hps-io-hash"
printf 'not-the-rbf\n' >"$test_root/not-the-rbf"
hash_file "$test_root/not-the-rbf" >"$bundle/payload/test.rbf.sha256"
cat >"$bundle/manifest.tsv" <<EOF
# sha256	size	mode	scope	destination	payload
$(hash_file "$bundle/payload/test.rbf")	$(file_size "$bundle/payload/test.rbf")	0644	fat	_Utility/test.rbf	test.rbf
$(hash_file "$bundle/payload/test.rbf.hps-io-hash")	$(file_size "$bundle/payload/test.rbf.hps-io-hash")	0644	fat	_Utility/test.rbf.hps-io-hash	test.rbf.hps-io-hash
$(hash_file "$bundle/payload/test.rbf.sha256")	$(file_size "$bundle/payload/test.rbf.sha256")	0644	fat	_Utility/test.rbf.sha256	test.rbf.sha256
EOF
if DE25_FAT_ROOT=$fat DE25_SYS_ROOT=$system \
    "$platform_root/sw/update_de25.sh" "$bundle" >/dev/null 2>&1; then
    echo "FAIL: updater accepted stale RBF SHA-256 metadata" >&2
    exit 1
fi
grep -qx 'installed rbf' "$fat/_Utility/test.rbf"

cat >"$bundle/manifest.tsv" <<EOF
# sha256	size	mode	scope	destination	payload
$(hash_file "$bundle/payload/test.rbf")	$(file_size "$bundle/payload/test.rbf")	0644	fat	_Utility/test.rbf	test.rbf
EOF
if DE25_FAT_ROOT=$fat DE25_SYS_ROOT=$system \
    "$platform_root/sw/update_de25.sh" "$bundle" >/dev/null 2>&1; then
    echo "FAIL: updater accepted an RBF without a compatibility sidecar" >&2
    exit 1
fi
grep -qx 'installed rbf' "$fat/_Utility/test.rbf"

prune_catalog=$test_root/prune-cores.tsv
prune_archive=$test_root/pruned
mkdir -p "$fat/_Console" "$fat/_Computer"
printf '%b\n' '# id\trbf' 'NES\t_Console/NES_20260814_FDCD.rbf' \
    'PC110\t_Computer/IBM_PC110_20260814_FDCD.rbf' \
    'Amiga\t_Computer/Minimig_20260812.rbf' >"$prune_catalog"
printf 'current\n' >"$fat/_Console/NES_20260814_FDCD.rbf"
printf 'old\n' >"$fat/_Console/NES_20260811.rbf"
printf 'old hash\n' >"$fat/_Console/NES_20260811.rbf.hps-io-hash"
printf 'diagnostic\n' >"$fat/_Console/NES_20260814_PLL_DIAG.rbf"
printf 'user\n' >"$fat/_Console/UserCore_20260101.rbf"
printf 'pc current\n' >"$fat/_Computer/IBM_PC110_20260814_FDCD.rbf"
printf 'legacy name\n' >"$fat/_Computer/IBM PC110_20260811.rbf"
printf 'pc old\n' >"$fat/_Computer/IBM_PC110_20260812.rbf"
printf 'fallback\n' >"$fat/_Computer/Minimig_20260811.rbf"
DE25_FAT_ROOT=$fat DE25_CORE_CATALOG=$prune_catalog \
    DE25_PRUNE_ARCHIVE=$prune_archive \
    "$platform_root/sw/mister-de25-prune-cores" >/dev/null
test -s "$fat/_Console/NES_20260814_FDCD.rbf"
test -s "$fat/_Console/UserCore_20260101.rbf"
test -s "$prune_archive/_Console/NES_20260811.rbf"
test -s "$prune_archive/_Console/NES_20260811.rbf.hps-io-hash"
test -s "$prune_archive/_Console/NES_20260814_PLL_DIAG.rbf"
test -s "$prune_archive/_Computer/IBM PC110_20260811.rbf"
test -s "$prune_archive/_Computer/IBM_PC110_20260812.rbf"
test -s "$fat/_Computer/Minimig_20260811.rbf"

echo "PASS: updater verification, compatibility and payload guards, backups, and transaction rollback"
