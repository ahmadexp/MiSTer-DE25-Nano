#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/de25-catalog-test.XXXXXXXX")
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

python3 "$platform_root/scripts/refresh-official-catalog.py" \
    --source "$platform_root/sim/core-catalog-fixture.md" \
    --source-label fixture \
    --source-revision 0123456789abcdef \
    --output "$work_dir/catalog.tsv" \
    --lock-output "$work_dir/catalog.lock"

[[ $(wc -l <"$work_dir/catalog.tsv" | tr -d ' ') -eq 5 ]]
grep -q $'_Computer\tFixture computer\tFixtureComputer\tno\thttps://github.com/MiSTer-devel/FixtureComputer_MiSTer.git\t\tMiSTer-devel_FixtureComputer_MiSTer\t' "$work_dir/catalog.tsv"
grep -q $'_Console\tFixture console\tFixtureConsole\tyes\thttps://github.com/MiSTer-devel/FixtureConsole_MiSTer.git\ttesting\tMiSTer-devel_FixtureConsole_MiSTer\t' "$work_dir/catalog.tsv"
grep -q $'_Utility\tFixture utility\tFixtureUtility\tno\thttps://github.com/MiSTer-devel/FixtureUtility_MiSTer.git\t\tMiSTer-devel_FixtureUtility_MiSTer\t' "$work_dir/catalog.tsv"
grep -q $'_Arcade\tFixture arcade\t\tyes\thttps://github.com/MiSTer-devel/Arcade-Fixture_MiSTer.git\t\tMiSTer-devel_Arcade-Fixture_MiSTer\t' "$work_dir/catalog.tsv"
grep -q $'^revision\t0123456789abcdef$' "$work_dir/catalog.lock"

python3 "$platform_root/scripts/verify-build-matrix.py" \
    --catalog "$platform_root/official-core-catalog.tsv" \
    --additional-catalog "$platform_root/local-core-catalog.tsv" \
    --lock "$platform_root/official-core-catalog.lock" \
    --status "$platform_root/port-status.tsv" \
    --matrix "$platform_root/build-matrix.tsv"

local_fixture=$work_dir/local.tsv
status_fixture=$work_dir/status.tsv
matrix_fixture=$work_dir/matrix.tsv
cat >"$local_fixture" <<'EOF'
category	name	home	sdram	repository	branch	source_id	comments
_Computer	Local fixture	LocalFixture	no	https://example.invalid/LocalFixture.git		LocalFixture	Supplemental core
EOF
cat >"$status_fixture" <<'EOF'
home	status	build_script	artifact	timing	hardware
LocalFixture	packaged	scripts/build-local.sh	artifacts/local/LocalFixture.rbf	pass	pending
EOF
python3 "$platform_root/scripts/generate-build-matrix.py" \
    --catalog "$work_dir/catalog.tsv" \
    --additional-catalog "$local_fixture" \
    --status "$status_fixture" \
    --output "$matrix_fixture"
[[ $(wc -l <"$matrix_fixture" | tr -d ' ') -eq 6 ]]
grep -q $'^_Computer\tLocal fixture\tLocalFixture\tno\t.*\tpackaged\tscripts/build-local.sh\tartifacts/local/LocalFixture.rbf\tpass\tpending\tSupplemental core$' \
    "$matrix_fixture"

packaged_fixture=$work_dir/packaged.tsv
cat >"$packaged_fixture" <<'EOF'
category	name	home	sdram	repository	branch	source_id	status	build_script	artifact	timing	hardware	comments
_Computer	Fixture	Fixture	no	https://example.invalid/Fixture.git		Fixture	packaged	scripts/build-fixture.sh	artifacts/fixture/Fixture.rbf	pass	pending	
EOF
grep -qx $'_Computer\tartifacts/fixture/Fixture.rbf' <(
    "$platform_root/scripts/list-packaged-artifacts.sh" "$packaged_fixture")
printf '%b\n' '_Computer\tDuplicate\tDuplicate\tno\thttps://example.invalid/Duplicate.git\t\tDuplicate\tpackaged\tscripts/build-duplicate.sh\tartifacts/other/Fixture.rbf\tpass\tpending\t' >>"$packaged_fixture"
if "$platform_root/scripts/list-packaged-artifacts.sh" "$packaged_fixture" \
    >/dev/null 2>&1; then
    echo "FAIL: packaged catalog accepted a duplicate FAT destination" >&2
    exit 1
fi

menu_fixture=$work_dir/menu-id.tsv
cat >"$menu_fixture" <<'EOF'
category	name	home	sdram	repository	branch	source_id	status	build_script	artifact	timing	hardware	comments
_Utility	Reserved menu ID	MENU	no	https://example.invalid/Menu.git		Menu	packaged	scripts/build-menu-fixture.sh	artifacts/menu-fixture/Menu.rbf	pass	pending	
EOF
if "$platform_root/scripts/make-runtime-core-catalog.sh" \
    "$work_dir/menu-runtime.tsv" "$menu_fixture" >/dev/null 2>&1; then
    echo "FAIL: runtime catalog accepted the reserved MENU core ID" >&2
    exit 1
fi

inventory=$work_dir/official-inventory.tsv
"$platform_root/scripts/official-port-inventory.sh" "$work_dir/not-fetched" \
    >"$inventory"
[[ $(wc -l <"$inventory" | tr -d ' ') -eq 307 ]]
grep -q $'^_Computer\tApple I\tAPPLE-I\tMiSTer-devel_Apple-I_MiSTer\tno\t' \
    "$inventory"

fixture_work=$work_dir/fixture-work
fixture_bare=$work_dir/fixture.git
fixture_sources=$work_dir/sources
mkdir -p "$fixture_work"
git -C "$fixture_work" init -q
git -C "$fixture_work" config user.email fixture@example.invalid
git -C "$fixture_work" config user.name Fixture
printf 'fixture\n' >"$fixture_work/README.md"
git -C "$fixture_work" add README.md
git -C "$fixture_work" commit -qm initial
git clone -q --bare "$fixture_work" "$fixture_bare"
fixture_revision=$(git -C "$fixture_work" rev-parse HEAD)
cat >"$work_dir/fetch-catalog.tsv" <<EOF
category	name	home	sdram	repository	branch	source_id	comments
_Computer	Fixture	Fixture	no	$fixture_bare		Fixture_Source	
EOF
fetch_result=$(DE25_OFFICIAL_CATALOG="$work_dir/fetch-catalog.tsv" \
    "$platform_root/scripts/fetch-official-core.sh" Fixture "$fixture_sources")
[[ $fetch_result == $'Fixture\tFixture_Source\t'"$fixture_revision" ]]
printf 'modified\n' >>"$fixture_sources/Fixture_Source/README.md"
if DE25_OFFICIAL_CATALOG="$work_dir/fetch-catalog.tsv" \
    "$platform_root/scripts/fetch-official-core.sh" Fixture "$fixture_sources" \
    >/dev/null 2>&1; then
    echo "FAIL: official core fetch overwrote a modified checkout" >&2
    exit 1
fi

echo "PASS: locked official core catalog, inventory, and safe source intake"
